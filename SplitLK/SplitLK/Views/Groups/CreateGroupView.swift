import SwiftUI
import CoreData

struct CreateGroupView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Environment(SyncService.self) private var sync

    @State private var model = GroupEditorViewModel()
    @State private var saveError: String?
    @FocusState private var newMemberFocused: Bool

    /// Currencies a user is most likely to need on a trip from Sri Lanka.
    private let currencies = ["LKR", "USD", "EUR", "GBP", "INR", "AUD", "SGD", "AED"]

    var body: some View {
        NavigationStack {
            Form {
                nameSection
                appearanceSection
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

    /// A colour and a symbol per group, so the list reads as a set of
    /// distinct things rather than eight identical rows. The preview updates
    /// as the pickers change, which is the point — the choice is visual, so
    /// showing the result beats describing it.
    private var appearanceSection: some View {
        Section {
            HStack {
                Spacer()
                Image(systemName: model.iconName)
                    .font(.system(size: 30))
                    .foregroundStyle(.white)
                    .frame(width: 72, height: 72)
                    .background(Circle().fill(Color(hex: model.colorHex).gradient))
                    .contentTransition(.symbolEffect(.replace))
                    .animation(.snappy, value: model.iconName)
                Spacer()
            }
            .padding(.vertical, 8)
            .accessibilityHidden(true)

            colorPicker
            iconPicker
        } header: {
            Text("Appearance")
        }
    }

    private var colorPicker: some View {
        HStack(spacing: 12) {
            ForEach(GroupStyle.colors, id: \.self) { hex in
                Button {
                    model.colorHex = hex
                } label: {
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 28, height: 28)
                        .overlay {
                            // A ring rather than a tick, so the swatch colour
                            // stays readable at this size.
                            Circle()
                                .strokeBorder(Color.primary, lineWidth: 2)
                                .padding(-3)
                                .opacity(model.colorHex == hex ? 1 : 0)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(colorName(for: hex))
                .accessibilityAddTraits(model.colorHex == hex ? [.isButton, .isSelected] : .isButton)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    private var iconPicker: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6),
                  spacing: 12) {
            ForEach(GroupStyle.icons, id: \.self) { symbol in
                Button {
                    model.iconName = symbol
                } label: {
                    Image(systemName: symbol)
                        .font(.system(size: 16))
                        .foregroundStyle(model.iconName == symbol ? Color(hex: model.colorHex) : .secondary)
                        .frame(width: 38, height: 38)
                        .background {
                            RoundedRectangle(cornerRadius: 9)
                                .fill(Color(hex: model.colorHex)
                                    .opacity(model.iconName == symbol ? 0.15 : 0))
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(symbolName(for: symbol))
                .accessibilityAddTraits(model.iconName == symbol ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.vertical, 6)
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

    /// VoiceOver cannot describe a colour or an SF Symbol, so both pickers
    /// would otherwise announce twenty identical unlabelled buttons.
    private func colorName(for hex: String) -> String {
        switch hex {
        case "4F46E5": return "Indigo"
        case "0891B2": return "Teal"
        case "16A34A": return "Green"
        case "D97706": return "Amber"
        case "DC2626": return "Red"
        case "DB2777": return "Pink"
        case "7C3AED": return "Purple"
        default:       return "Slate"
        }
    }

    private func symbolName(for symbol: String) -> String {
        switch symbol {
        case "person.3.fill":       return "People"
        case "airplane":            return "Trip"
        case "house.fill":          return "Home"
        case "fork.knife":          return "Dining"
        case "beach.umbrella.fill": return "Beach"
        case "car.fill":            return "Road trip"
        case "cart.fill":           return "Shopping"
        case "music.note":          return "Night out"
        case "gift.fill":           return "Celebration"
        case "graduationcap.fill":  return "University"
        case "sportscourt.fill":    return "Sport"
        default:                    return "Camping"
        }
    }

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
            let group = try model.save(in: context)
            // Started before dismissing so the upload is not racing the
            // view's teardown. The group exists locally either way; uploading
            // is what makes the invite code usable, so a failure is not fatal.
            Task { await sync.push(group) }
            dismiss()
        } catch {
            context.rollback()
            saveError = error.localizedDescription
        }
    }
}
