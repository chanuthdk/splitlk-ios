import SwiftUI
import CoreData

struct CreateGroupView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var model = GroupEditorViewModel()
    @State private var saveError: String?
    @FocusState private var newMemberFocused: Bool

    /// Currencies a user is most likely to need on a trip from Sri Lanka.
    private let currencies = ["LKR", "USD", "EUR", "GBP", "INR", "AUD", "SGD", "AED"]

    var body: some View {
        NavigationStack {
            Form {
                nameSection
                membersSection
                inviteSection
            }
            .navigationTitle("New Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Create") { save() }
                        .disabled(!model.canSave)
                }
            }
            .alert("Couldn't create the group", isPresented: .constant(saveError != nil)) {
                Button("OK") { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
        }
    }

    // MARK: - Sections

    private var nameSection: some View {
        Section {
            TextField("Group name", text: $model.name)
                .textInputAutocapitalization(.words)

            Picker("Currency", selection: $model.currencyCode) {
                ForEach(currencies, id: \.self) { Text($0).tag($0) }
            }
        } header: {
            Text("Details")
        } footer: {
            Text("Bills in this group are tracked in \(model.currencyCode).")
        }
    }

    private var membersSection: some View {
        Section {
            ForEach(model.members) { member in
                HStack(spacing: 12) {
                    Circle()
                        .fill(Color(hex: member.colorHex))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Text(initials(for: member.name))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                        )

                    Text(member.isMe ? "\(member.name) (You)" : member.name)

                    Spacer()
                }
                .accessibilityElement(children: .combine)
            }
            .onDelete { model.removeMembers(at: $0) }

            HStack {
                TextField("Add a person", text: $model.newMemberName)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .focused($newMemberFocused)
                    .onSubmit {
                        model.addMember()
                        newMemberFocused = true
                    }

                Button {
                    model.addMember()
                    newMemberFocused = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .disabled(model.newMemberName.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel("Add this person to the group")
            }
        } header: {
            Text("Members")
        } footer: {
            if let hint = model.validationHint {
                Text(hint)
            } else {
                Text("Swipe a person to remove them. You can't remove yourself.")
            }
        }
    }

    private var inviteSection: some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.inviteCode)
                        .font(.title3.monospaced().weight(.semibold))
                    Text("Share this so friends can join")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    UIPasteboard.general.string = model.inviteCode
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Copy the invite code")
            }
            .padding(.vertical, 4)
        } header: {
            Text("Invite Code")
        }
    }

    // MARK: - Helpers

    private func initials(for name: String) -> String {
        name.split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
            .map(String.init)
            .joined()
            .uppercased()
    }

    private func save() {
        do {
            try model.save(in: context)
            dismiss()
        } catch {
            context.rollback()
            saveError = error.localizedDescription
        }
    }
}
