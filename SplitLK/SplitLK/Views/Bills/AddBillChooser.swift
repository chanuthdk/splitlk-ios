import SwiftUI
import CoreData

struct AddBillChooser: View {
    let group: CDGroup
    @Environment(\.dismiss) private var dismiss

    @State private var path: [Route] = []
    @State private var prefilled: BillEditorViewModel?
    @State private var duplicate: DuplicateDetector.Match?
    @State private var scannedImage: UIImage?

    enum Route: Hashable {
        case scan
        case duplicate(UUID)   // identity so a second scan rebuilds the screen
        case manual(UUID)
    }

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
                    prefilled = nil
                    path.append(.manual(UUID()))
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
                        handleScan(scan, parsed)
                    }

                case .duplicate:
                    if let duplicate {
                        DuplicateWarningView(
                            match: duplicate,
                            newImage: scannedImage,
                            onContinue: { path.append(.manual(UUID())) },
                            onCancel: { dismiss() }
                        )
                        .navigationBarBackButtonHidden()
                    }

                case .manual:
                    AddBillView(group: group, prefilled: prefilled)
                }
            }
        }
    }

    // MARK: - Scan handling

    /// A scanned receipt is checked against the group's existing bills before
    /// the user starts assigning it, so a duplicate claim is caught at the
    /// point it would be entered rather than after the balances have moved.
    private func handleScan(_ scan: ReceiptScanner.ScanResult,
                            _ parsed: ReceiptParser.ParsedReceipt) {
        let model = BillEditorViewModel(group: group)
        model.apply(parsed, scan: scan)
        prefilled = model
        scannedImage = scan.correctedImage

        if let match = DuplicateDetector.findDuplicate(of: scan.featurePrint, in: group) {
            duplicate = match
            path.append(.duplicate(UUID()))
        } else {
            duplicate = nil
            path.append(.manual(UUID()))
        }
    }

    // MARK: - Pieces

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
        .accessibilityLabel("\(title). \(subtitle)")
    }
}
