import SwiftUI
import CoreData

struct AddBillView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var model: BillEditorViewModel
    @State private var saveError: String?

    init(group: CDGroup) {
        _model = State(initialValue: BillEditorViewModel(group: group))
    }

    var body: some View {
        Form {
            detailsSection
            itemsSection
            chargesSection
            splitSection
            totalsSection
        }
        .navigationTitle("Add Bill")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { save() }
                    .disabled(!model.canSave)
            }
        }
        .alert("Couldn't save", isPresented: .constant(saveError != nil)) {
            Button("OK") { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }

    // MARK: - Sections

    private var detailsSection: some View {
        Section("Details") {
            TextField("Merchant", text: $model.merchant)
                .textInputAutocapitalization(.words)

            DatePicker("Date", selection: $model.date, displayedComponents: .date)

            Picker("Paid by", selection: $model.payerID) {
                ForEach(model.group.memberList, id: \.memberID) { member in
                    Text(member.displayName).tag(Optional(member.memberID))
                }
            }
        }
    }

    private var itemsSection: some View {
        Section {
            ForEach($model.items) { $item in
                ItemEditorRow(item: $item, group: model.group) { memberID in
                    model.toggle(memberID, on: item.id)
                }
            }
            .onDelete { model.removeItems(at: $0) }

            Button {
                model.addItem()
            } label: {
                Label("Add item", systemImage: "plus.circle.fill")
            }
        } header: {
            Text("Items")
        } footer: {
            if model.unassignedCount > 0 {
                Text("\(model.unassignedCount) item\(model.unassignedCount == 1 ? "" : "s") unassigned — these will be split equally.")
            }
        }
    }

    private var chargesSection: some View {
        Section("Charges") {
            DecimalField(title: "Service charge", value: $model.serviceCharge)
            DecimalField(title: "Tax", value: $model.tax)
        }
    }

    private var splitSection: some View {
        Section("Split") {
            Picker("Method", selection: $model.mode) {
                ForEach([SplitMode.equally, .byItem]) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    private var totalsSection: some View {
        Section("Summary") {
            LabeledContent("Subtotal", value: Money.format(model.itemsSubtotal))
            LabeledContent("Total", value: Money.format(model.total))
                .font(.headline)

            let shares = model.previewShares()
            ForEach(model.group.memberList, id: \.memberID) { member in
                let amount = shares[member.memberID] ?? 0
                if amount > 0 {
                    LabeledContent(member.displayName, value: Money.format(amount))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Actions

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

struct ItemEditorRow: View {
    @Binding var item: BillEditorViewModel.DraftItem
    let group: CDGroup
    let onToggle: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Item name", text: $item.name)
                DecimalField(title: "", value: $item.amount)
                    .frame(width: 90)
            }

            Picker("Category", selection: $item.category) {
                ForEach(SpendingCategory.allCases) { category in
                    Label(category.label, systemImage: category.symbolName).tag(category)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(group.memberList, id: \.memberID) { member in
                        let isOn = item.assignees.contains(member.memberID)
                        Button {
                            onToggle(member.memberID)
                        } label: {
                            Text(member.displayName)
                                .font(.footnote)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule().fill(isOn ? Color(hex: "4F46E5") : Color(.systemGray5))
                                )
                                .foregroundStyle(isOn ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(member.displayName), \(isOn ? "assigned" : "not assigned")")
                        .accessibilityAddTraits(isOn ? [.isSelected] : [])
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.vertical, 4)
    }
}

/// A text field that edits a Decimal without losing precision through Double.
struct DecimalField: View {
    let title: String
    @Binding var value: Decimal

    var body: some View {
        TextField(title, text: Binding(
            get: { value == 0 ? "" : "\(value)" },
            set: { value = Decimal(string: $0) ?? 0 }
        ))
        .keyboardType(.decimalPad)
        .multilineTextAlignment(title.isEmpty ? .trailing : .leading)
    }
}
