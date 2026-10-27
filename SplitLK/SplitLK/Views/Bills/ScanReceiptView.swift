import SwiftUI
import PhotosUI
import CoreData

struct ScanReceiptView: View {
    let group: CDGroup
    let onParsed: (ReceiptScanner.ScanResult, ReceiptParser.ParsedReceipt) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var pickerItem: PhotosPickerItem?
    @State private var request: ScanRequest?
    /// The request already acted on. A `.task` restarts when its view appears
    /// again, and this screen reappears every time the user comes back from
    /// the bill editor — without this, coming back re-ran the last scan and
    /// pushed the editor a second time on its own.
    @State private var handledRequestID: UUID?
    @State private var stage: Stage = .choosing
    @State private var preview: UIImage?

    enum Stage: Equatable {
        case choosing
        case working(String)
        case failed(String)
    }

    /// Wraps the chosen photo with a fresh id so picking the *same* photo
    /// again still counts as a new request. Keying the work on the picker
    /// item alone meant a failed scan could not be retried on that photo,
    /// because the item compared equal and the task never re-ran.
    private struct ScanRequest: Equatable {
        let id = UUID()
        let item: PhotosPickerItem
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
                            .strokeBorder(Palette.stamp, lineWidth: 2)
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
            request = ScanRequest(item: item)
        }
        // A `.task` tied to the request rather than a free-standing `Task`,
        // so leaving this screen cancels the scan. Previously the work
        // carried on after Cancel and then called back, which pushed the
        // bill editor for a receipt the user had already abandoned.
        .task(id: request) {
            await runPendingScan()
        }
    }

    /// Runs the newest request at most once, whatever makes the task start.
    @MainActor
    private func runPendingScan() async {
        guard let request else { return }

        guard request.id != handledRequestID else {
            // Back on a scan that was abandoned part-way. Its task was
            // cancelled and will not resume, so the screen is put back into a
            // usable state instead of showing a spinner that never finishes.
            if case .working = stage { stage = .choosing }
            return
        }

        handledRequestID = request.id
        await handle(request.item)
    }

    /// Explicitly main-actor: it writes view state, and the closure `.task`
    /// takes is sendable rather than isolated, so without this the updates
    /// would land off the main actor.
    @MainActor
    private func handle(_ item: PhotosPickerItem) async {
        stage = .working("Loading photo…")

        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            guard !Task.isCancelled else { return }
            stage = .failed("That file couldn't be opened as an image.")
            return
        }

        guard !Task.isCancelled else { return }
        preview = image
        stage = .working("Reading receipt…")

        do {
            let result = try await ReceiptScanner.scan(image)
            let parsed = ReceiptParser.parse(lines: result.lines)

            // Cancellation is cooperative and the Vision work does not check
            // for it, so the result can arrive after the screen has gone.
            // Acting on it here is what used to add an abandoned bill.
            guard !Task.isCancelled else { return }

            guard !parsed.items.isEmpty else {
                stage = .failed("No items could be read. Try a sharper photo, or enter the bill manually.")
                return
            }

            preview = result.correctedImage
            // Reset before handing over, so going back from the editor shows
            // the scanned receipt and a "Try Another Photo" button rather
            // than a spinner that can never finish.
            stage = .choosing
            onParsed(result, parsed)
        } catch {
            guard !Task.isCancelled else { return }
            stage = .failed(error.localizedDescription)
        }
    }
}
