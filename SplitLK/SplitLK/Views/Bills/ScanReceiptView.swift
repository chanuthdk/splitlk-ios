import SwiftUI
import PhotosUI
import CoreData

struct ScanReceiptView: View {
    let group: CDGroup
    let onParsed: (ReceiptScanner.ScanResult, ReceiptParser.ParsedReceipt) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var pickerItem: PhotosPickerItem?
    @State private var stage: Stage = .choosing
    @State private var preview: UIImage?

    enum Stage: Equatable {
        case choosing
        case working(String)
        case failed(String)
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            if let preview {
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color(hex: "4F46E5"), lineWidth: 2)
                    )
            } else {
                Image(systemName: "doc.text.viewfinder")
                    .font(.system(size: 64))
                    .foregroundStyle(.secondary)
            }

            switch stage {
            case .choosing:
                Text("Choose a receipt photo")
                    .font(.headline)
                Text("The text is read on your device. Nothing is uploaded.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

            case .working(let message):
                ProgressView()
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

            case .failed(let message):
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.orange)
                Text("Couldn't read this receipt")
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            PhotosPicker(selection: $pickerItem, matching: .images) {
                Text(preview == nil ? "Choose Photo" : "Try Another Photo")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .navigationTitle("Scan Receipt")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await handle(item) }
        }
    }

    private func handle(_ item: PhotosPickerItem) async {
        stage = .working("Loading photo…")

        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            stage = .failed("That file couldn't be opened as an image.")
            return
        }

        preview = image
        stage = .working("Reading receipt…")

        do {
            let result = try await ReceiptScanner.scan(image)
            let parsed = ReceiptParser.parse(lines: result.lines)

            print("OCR lines: \(result.lines.count)")
            print("parsed items: \(parsed.items.map { ($0.name, $0.amount) })")
            print("total: \(String(describing: parsed.total))")
            guard !parsed.items.isEmpty else {
                stage = .failed("No items could be read. Try a sharper photo, or enter the bill manually.")
                return
            }
            print("rows: \(ReceiptParser.groupIntoRows(result.lines).map(\.text))")

            preview = result.correctedImage
            onParsed(result, parsed)
        } catch {
            stage = .failed(error.localizedDescription)
        }
    }
}
