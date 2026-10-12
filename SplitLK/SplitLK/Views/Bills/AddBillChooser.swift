import SwiftUI
import CoreData

struct AddBillChooser: View {
    let group: CDGroup
    @Environment(\.dismiss) private var dismiss

    @State private var path: [Route] = []
    @State private var prefilled: BillEditorViewModel?

    enum Route: Hashable { case scan, manual }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 16) {
                optionCard(title: "Scan Receipt",
                           subtitle: "Auto-read items and prices",
                           systemImage: "doc.text.viewfinder") {
                    path.append(.scan)
                }

                optionCard(title: "Enter Manually",
                           subtitle: "Type the bill yourself",
                           systemImage: "keyboard") {
                    path.append(.manual)
                }

                Spacer()
            }
            .padding(20)
            .navigationTitle("Add Bill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .scan:
                    ScanReceiptView(group: group) { scan, parsed in
                        let model = BillEditorViewModel(group: group)
                        model.apply(parsed, scan: scan)
                        prefilled = model
                        path = [.manual]
                    }
                case .manual:
                    AddBillView(group: group, prefilled: prefilled)
                }
            }
        }
    }

    private func optionCard(title: String,
                            subtitle: String,
                            systemImage: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 22))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: "4F46E5")))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemGroupedBackground)))
        }
        .buttonStyle(.plain)
    }
}
