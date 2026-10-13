import SwiftUI
import CoreData

/// Shown when a scanned receipt closely matches one already in the group.
/// The match is surfaced for the user to judge rather than rejected
/// outright, because a repeat visit to the same restaurant produces a
/// genuinely similar receipt.
struct DuplicateWarningView: View {
    let match: DuplicateDetector.Match
    let newImage: UIImage?
    let onContinue: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.orange)

            VStack(spacing: 8) {
                Text("Possible duplicate")
                    .font(.title2.bold())

                Text(explanation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            HStack(alignment: .top, spacing: 16) {
                thumbnail(image: newImage, label: "New", caption: "Just scanned")
                thumbnail(image: storedImage, label: "Existing", caption: existingCaption)
            }
            .padding(.top, 4)

            Label("\(match.confidencePercent)% match",
                  systemImage: "equal.square")
                .font(.footnote.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.orange.opacity(0.15)))
                .foregroundStyle(.orange)

            Spacer()

            VStack(spacing: 10) {
                Button("Add it anyway") { onContinue() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)

                Button("Cancel", role: .cancel) { onCancel() }
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Pieces

    private func thumbnail(image: UIImage?, label: String, caption: String) -> some View {
        VStack(spacing: 6) {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "doc.text")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 120, height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color(.separator), lineWidth: 1)
            )

            Text(label)
                .font(.subheadline.weight(.medium))
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) receipt, \(caption)")
    }

    private var storedImage: UIImage? {
        match.bill.receiptImage.flatMap(UIImage.init(data:))
    }

    private var explanation: String {
        let payer = match.bill.payer?.displayName ?? "someone"
        let date = (match.bill.date ?? Date()).formatted(.dateTime.day().month(.wide))
        return "This looks like \(match.bill.displayMerchant), already added by \(payer) on \(date)."
    }

    private var existingCaption: String {
        Money.format(match.bill.totalAmount)
    }
}
