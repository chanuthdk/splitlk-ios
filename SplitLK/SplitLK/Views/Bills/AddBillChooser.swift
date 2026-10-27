import SwiftUI
import CoreData

struct AddBillChooser: View {
    let group: CDGroup
    /// Reported to the presenter so the confirmation can be shown on the
    /// group, after this sheet has closed.
    var onSaved: ((String) -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var path: [Route] = []

    /// The scanned bill travels *inside* the route rather than in a separate
    /// piece of state beside it.
    ///
    /// It used to be held in its own `@State` that was set just before the
    /// push. That is two state changes, and SwiftUI does not promise to apply
    /// them in one update — so the editor could be built while the scanned
    /// draft was still nil and open with no items, which is exactly what
    /// happened. Carrying the payload in the route makes the push a single
    /// change, and the destination cannot be built without it.
    enum Route: Hashable {
        case scan
        case duplicate(DuplicateRoute)
        case manual(ManualRoute)
    }

    /// Identity is the id alone, so a second scan of the same receipt still
    /// counts as a new screen. `BillEditorViewModel` is a reference type and
    /// deliberately not part of the comparison.
    struct ManualRoute: Hashable {
        let id = UUID()
        let prefilled: BillEditorViewModel?

        static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    struct DuplicateRoute: Hashable {
        let id = UUID()
        let match: DuplicateDetector.Match
        let image: UIImage?
        let prefilled: BillEditorViewModel

        static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
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
                    path.append(.manual(ManualRoute(prefilled: nil)))
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

                case .duplicate(let route):
                    DuplicateWarningView(
                        match: route.match,
                        newImage: route.image,
                        onContinue: {
                            path.append(.manual(ManualRoute(prefilled: route.prefilled)))
                        },
                        onCancel: { dismiss() }
                    )
                    .navigationBarBackButtonHidden()

                case .manual(let route):
                    AddBillView(group: group, prefilled: route.prefilled) { message in
                        onSaved?(message)
                        dismiss()
                    }
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

        if let match = DuplicateDetector.findDuplicate(of: scan.featurePrint, in: group) {
            path.append(.duplicate(DuplicateRoute(match: match,
                                                  image: scan.correctedImage,
                                                  prefilled: model)))
        } else {
            path.append(.manual(ManualRoute(prefilled: model)))
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
                    .background(RoundedRectangle(cornerRadius: 12).fill(Palette.stamp))

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
