import SwiftUI
import CoreData

struct AddBillView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var model: BillEditorViewModel
    @State private var saveError: String?

    /// Called with a short confirmation once the bill is in the store. The
    /// view does not dismiss itself, because it sits inside a pushed stack
    /// and `dismiss()` here only pops back to the chooser — the caller owns
    /// the sheet and is the one that can close it.
    private let onSaved: ((String) -> Void)?

    init(group: CDGroup,
         prefilled: BillEditorViewModel? = nil,
         onSaved: ((String) -> Void)? = nil) {
        _model = State(initialValue: prefilled ?? BillEditorViewModel(group: group))
        self.onSaved = onSaved
    }

    var body: some View {
        Form {
            // Inside the Form, not above it. A Section outside a Form has no
            // container to style it, so this warning used to render as bare
            // text wedged above the first row.
            if !model.reconciles, let scanned = model.scannedTotal {
                Section {
                    Label("Items total \(Money.format(model.total)) but the receipt shows \(Money.format(scanned)). Check for missing or misread items.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }

            detailsSection
            itemsSection
            chargesSection
            splitSection
            totalsSection
        }
        .scrollContentBackground(.hidden)
        .background(Palette.paper)
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
                ItemEditorRow(item: $item,
                              group: model.group,
                              onToggle: { memberID in
                                  model.toggle(memberID, on: item.id)
                              },
                              onCategoryChange: { category in
                                  model.setCategory(category, on: item.id)
                              })
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

    /// Laid out the way the foot of a printed bill is: the figures that make
    /// up the total, a tear line, the total itself, then who owes what. The
    /// amounts are tabular so they line up on the decimal down the column.
    private var totalsSection: some View {
        Section("Summary") {
            VStack(spacing: 9) {
                figureRow("Subtotal", model.itemsSubtotal)

                if model.serviceCharge > 0 {
                    figureRow("Service charge", model.serviceCharge)
                }
                if model.tax > 0 {
                    figureRow("Tax", model.tax)
                }

                TearLine()
                    .padding(.vertical, 2)

                figureRow("Total", model.total, emphasised: true)
            }
            .padding(.vertical, 4)

            let shares = model.previewShares()
            ForEach(model.group.memberList, id: \.memberID) { member in
                let amount = shares[member.memberID] ?? 0
                if amount > 0 {
                    LabeledContent(member.displayName) {
                        Text(Money.format(amount))
                            .font(.money(.subheadline))
                    }
                    .font(.subheadline)
                    .foregroundStyle(Palette.inkSoft)
                }
            }
        }
    }

    private func figureRow(_ label: String, _ amount: Decimal, emphasised: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(emphasised ? .headline : .subheadline)
                .foregroundStyle(emphasised ? Palette.ink : Palette.inkSoft)
            Spacer(minLength: 12)
            Text(Money.format(amount))
                .font(.money(emphasised ? .headline : .subheadline,
                             weight: emphasised ? .semibold : .regular))
                .foregroundStyle(emphasised ? Palette.ink : Palette.inkSoft)
                .contentTransition(.numericText())
                .animation(.snappy, value: amount)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Actions

    private func save() {
        do {
            let bill = try model.save(in: context)
            let name = bill.displayMerchant
            let message = "\(name) added · \(Money.format(bill.totalAmount))"

            if let onSaved {
                onSaved(message)
            } else {
                dismiss()
            }
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
    let onCategoryChange: (SpendingCategory) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Item name", text: $item.name)
                DecimalField(title: "", value: $item.amount)
                    .frame(width: 90)
            }

            Picker("Category", selection: Binding(
                get: { item.category },
                set: { onCategoryChange($0) }
            )) {
                ForEach(SpendingCategory.allCases) { category in
                    Label(category.label, systemImage: category.symbolName).tag(category)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .accessibilityLabel("Category for \(item.name.isEmpty ? "this item" : item.name)")

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
                                    Capsule().fill(isOn ? Palette.stamp : Color(.systemGray5))
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
