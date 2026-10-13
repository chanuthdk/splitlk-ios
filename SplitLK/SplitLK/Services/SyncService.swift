import Foundation
import CoreData
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore

/// Syncs groups through Cloud Firestore so every member of a trip sees the
/// same bills and balances.
///
/// Core Data stays the source of truth on the device: the app reads and
/// writes locally and works fully offline, and this service pushes those
/// changes up and merges other people's changes back down. That ordering is
/// deliberate — a shared-expenses app is most useful exactly when you are
/// abroad with patchy signal, so nothing in the UI waits on the network.
@Observable
@MainActor
final class SyncService {

    enum Status: Equatable {
        case idle
        case syncing
        case synced(Date)
        case failed(String)
    }

    private(set) var status: Status = .idle
    private(set) var uid: String?

    private var listeners: [UUID: ListenerRegistration] = [:]
    private let database = Firestore.firestore()

    // MARK: - Session

    /// Signs in anonymously. Anonymous auth is enough here because a group is
    /// identified by its invite code rather than by who you are, and it keeps
    /// the user from having to make an account before splitting a dinner bill.
    @discardableResult
    func signIn() async throws -> String {
        if let existing = Auth.auth().currentUser?.uid {
            uid = existing
            return existing
        }

        let result = try await Auth.auth().signInAnonymously()
        uid = result.user.uid
        return result.user.uid
    }

    // MARK: - Pushing

    /// Uploads a group and everything in it.
    func push(_ group: CDGroup) async {
        status = .syncing
        do {
            let uid = try await signIn()
            let bundle = SyncMapper.bundle(from: group, memberUids: memberUids(for: group, including: uid))
            try await upload(bundle)
            status = .synced(Date())
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    private func upload(_ bundle: GroupBundle) async throws {
        let groupRef = database.collection("groups").document(bundle.group.id)

        // A batch keeps the group and its contents consistent: another member
        // never sees a bill whose payer has not arrived yet.
        let batch = database.batch()
        try batch.setData(from: bundle.group, forDocument: groupRef, merge: true)

        for member in bundle.members {
            try batch.setData(from: member,
                              forDocument: groupRef.collection("members").document(member.id),
                              merge: true)
        }
        for bill in bundle.bills {
            try batch.setData(from: bill,
                              forDocument: groupRef.collection("bills").document(bill.id),
                              merge: true)
        }
        for settlement in bundle.settlements {
            try batch.setData(from: settlement,
                              forDocument: groupRef.collection("settlements").document(settlement.id),
                              merge: true)
        }

        try await batch.commit()
    }

    /// The uids allowed to touch this group. Members who have not joined from
    /// their own device yet have no uid, so the list only grows as people join.
    private func memberUids(for group: CDGroup, including uid: String) -> [String] {
        var uids = Set(group.memberList.compactMap(\.linkedUid))
        uids.insert(uid)
        return Array(uids)
    }

    // MARK: - Joining

    /// Finds a group by its invite code, claims a seat in it, and writes it
    /// into Core Data.
    @discardableResult
    func join(inviteCode: String,
              as memberName: String,
              in context: NSManagedObjectContext) async throws -> CDGroup {
        status = .syncing
        do {
            let uid = try await signIn()
            let code = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

            let snapshot = try await database.collection("groups")
                .whereField("inviteCode", isEqualTo: code)
                .limit(to: 1)
                .getDocuments()

            guard let document = snapshot.documents.first else {
                throw SyncError.groupNotFound
            }

            let bundle = try await download(groupID: document.documentID)
            let group = try SyncMapper.apply(bundle, in: context)

            try await claimSeat(in: group, groupID: document.documentID,
                                uid: uid, preferredName: memberName, context: context)

            status = .synced(Date())
            return group
        } catch {
            status = .failed(error.localizedDescription)
            throw error
        }
    }

    private func download(groupID: String) async throws -> GroupBundle {
        let groupRef = database.collection("groups").document(groupID)

        let groupDoc = try await groupRef.getDocument()
        guard let group = try? groupDoc.data(as: GroupDTO.self) else {
            throw SyncError.malformedPayload
        }

        async let members = groupRef.collection("members").getDocuments()
        async let bills = groupRef.collection("bills").getDocuments()
        async let settlements = groupRef.collection("settlements").getDocuments()

        return GroupBundle(
            group: group,
            members: try await members.documents.compactMap { try? $0.data(as: MemberDTO.self) },
            bills: try await bills.documents.compactMap { try? $0.data(as: BillDTO.self) },
            settlements: try await settlements.documents.compactMap { try? $0.data(as: SettlementDTO.self) }
        )
    }

    /// Links this device to one of the group's members. An unclaimed member
    /// with a matching name is taken over, so a trip organiser can add
    /// everyone up front and each person simply claims their own row.
    private func claimSeat(in group: CDGroup,
                           groupID: String,
                           uid: String,
                           preferredName: String,
                           context: NSManagedObjectContext) async throws {
        let name = preferredName.trimmingCharacters(in: .whitespaces)

        let mine = group.memberList.first { $0.linkedUid == uid }
            ?? group.memberList.first {
                $0.linkedUid == nil && $0.displayName.caseInsensitiveCompare(name) == .orderedSame
            }

        let member: CDMember
        if let mine {
            member = mine
        } else {
            member = CDMember(context: context)
            member.id = UUID()
            member.name = name.isEmpty ? "Me" : name
            member.colorHex = GroupEditorViewModel.palette[group.memberList.count % GroupEditorViewModel.palette.count]
            member.group = group
        }

        member.linkedUid = uid
        // Exactly one member represents the person holding this phone.
        for other in group.memberList where other != member {
            other.isMe = false
        }
        member.isMe = true

        try context.save()

        let groupRef = database.collection("groups").document(groupID)
        try await groupRef.updateData([
            "memberUids": FieldValue.arrayUnion([uid])
        ])
        try groupRef.collection("members").document(member.memberID.uuidString)
            .setData(from: MemberDTO(id: member.memberID.uuidString,
                                     name: member.displayName,
                                     colorHex: member.colorHex ?? "4F46E5",
                                     linkedUid: uid),
                     merge: true)
    }

    // MARK: - Live updates

    /// Watches a group for changes made by other members.
    func startListening(to group: CDGroup, context: NSManagedObjectContext) {
        let id = group.groupID
        guard listeners[id] == nil else { return }

        let groupRef = database.collection("groups").document(id.uuidString)

        listeners[id] = groupRef.collection("bills")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self, error == nil, let snapshot else { return }
                // Ignore the echo of our own writes; they are already local.
                guard !snapshot.metadata.hasPendingWrites else { return }

                Task { @MainActor in
                    await self.refresh(groupID: id.uuidString, in: context)
                }
            }
    }

    func stopListening(to group: CDGroup) {
        let id = group.groupID
        listeners[id]?.remove()
        listeners[id] = nil
    }

    func stopAll() {
        listeners.values.forEach { $0.remove() }
        listeners.removeAll()
    }

    private func refresh(groupID: String, in context: NSManagedObjectContext) async {
        do {
            let bundle = try await download(groupID: groupID)
            try SyncMapper.apply(bundle, in: context)
            status = .synced(Date())
        } catch {
            status = .failed(error.localizedDescription)
        }
    }
}
