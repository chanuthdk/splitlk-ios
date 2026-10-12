import Foundation
import Vision
import CoreImage
import UIKit

/// Runs the on-device Vision pipeline over a receipt photograph:
/// document detection, perspective correction, text recognition and
/// a perceptual fingerprint used for duplicate detection.
enum ReceiptScanner {

    struct Line {
        let text: String
        /// Normalised position, origin bottom-left, as Vision reports it.
        let box: CGRect
        let confidence: Float
    }

    struct ScanResult {
        let lines: [Line]
        let correctedImage: UIImage
        let featurePrint: Data?
        var rawText: String { lines.map(\.text).joined(separator: "\n") }
    }

    enum ScanError: Error, LocalizedError {
        case invalidImage
        case noTextFound

        var errorDescription: String? {
            switch self {
            case .invalidImage: return "That image couldn't be read."
            case .noTextFound:  return "No text was found on this receipt."
            }
        }
    }

    private static let ciContext = CIContext()

    static func scan(_ image: UIImage) async throws -> ScanResult {
        guard let cgImage = image.cgImage else { throw ScanError.invalidImage }

        // 1. Flatten the receipt first. Recognition accuracy drops sharply on
        //    angled or skewed photos, so geometry is corrected before OCR.
        let corrected = try await correctPerspective(cgImage: cgImage) ?? CIImage(cgImage: cgImage)

        // 2. Recognise the text on the corrected image.
        let lines = try await recognizeText(in: corrected)
        guard !lines.isEmpty else { throw ScanError.noTextFound }

        // 3. Fingerprint the corrected image for duplicate detection.
        let print = try? await featurePrint(for: corrected)

        let output = ciContext.createCGImage(corrected, from: corrected.extent)
        let uiImage = output.map { UIImage(cgImage: $0) } ?? image

        return ScanResult(lines: lines, correctedImage: uiImage, featurePrint: print)
    }

    // MARK: - Step 1: perspective correction

    private static func correctPerspective(cgImage: CGImage) async throws -> CIImage? {
        let request = VNDetectDocumentSegmentationRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        try handler.perform([request])

        guard let observation = request.results?.first as? VNRectangleObservation else {
            return nil   // no document edge found, carry on with the original
        }

        let input = CIImage(cgImage: cgImage)
        let size = input.extent.size

        func denormalise(_ point: CGPoint) -> CGPoint {
            CGPoint(x: point.x * size.width, y: point.y * size.height)
        }

        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else { return nil }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgPoint: denormalise(observation.topLeft)), forKey: "inputTopLeft")
        filter.setValue(CIVector(cgPoint: denormalise(observation.topRight)), forKey: "inputTopRight")
        filter.setValue(CIVector(cgPoint: denormalise(observation.bottomLeft)), forKey: "inputBottomLeft")
        filter.setValue(CIVector(cgPoint: denormalise(observation.bottomRight)), forKey: "inputBottomRight")

        return filter.outputImage
    }

    // MARK: - Step 2: text recognition

    private static func recognizeText(in image: CIImage) async throws -> [Line] {
        let request = VNRecognizeTextRequest()
        // Accurate is slower but far better on small printed receipt type.
        request.recognitionLevel = .accurate
        // Receipts are not prose, so language correction does more harm than good.
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US"]

        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        try handler.perform([request])

        let observations = request.results ?? []
        return observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return Line(text: candidate.string,
                        box: observation.boundingBox,
                        confidence: candidate.confidence)
        }
    }

    // MARK: - Step 3: fingerprint

    private static func featurePrint(for image: CIImage) async throws -> Data? {
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        try handler.perform([request])

        guard let observation = request.results?.first as? VNFeaturePrintObservation else {
            return nil
        }
        return observation.data
    }

    /// Distance between two fingerprints. Smaller means more alike.
    static func distance(_ a: Data, _ b: Data) -> Float? {
        let first = VNFeaturePrintObservation()
        let second = VNFeaturePrintObservation()
        guard first.setValue(a, forKey: "data") == () else { return nil }
        _ = second.setValue(b, forKey: "data")

        var result: Float = 0
        do {
            try first.computeDistance(&result, to: second)
            return result
        } catch {
            return nil
        }
    }
}
