import SwiftUI
import CoreData

/// Joins an existing group using the invite code its creator shared.
struct JoinGroupView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var code = ""
    @State private var name = ""
    @State private var isJoining = false
    @State private var errorMessage: String?

    let sync: SyncService

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Invite code", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())

                    TextField("Your name", text: $name)
                        .textInputAutocapitalization(.words)
                } header: {
                    Text("Join a Group")
                } footer: {
                    Text("Ask whoever created the group for the code. Your name is how the others will see you.")
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Join Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(isJoining)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isJoining {
                        ProgressView()
                    } else {
                        Button("Join") { join() }
                            .disabled(!canJoin)
                    }
                }
            }
        }
    }

    private var canJoin: Bool {
        code.trimmingCharacters(in: .whitespaces).count >= 4
            && !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func join() {
        isJoining = true
        errorMessage = nil

        Task {
            do {
                try await sync.join(inviteCode: code, as: name, in: context)
                dismiss()
            } catch {
                errorMessage = error.detailedDescription
            }
            isJoining = false
        }
    }
}
