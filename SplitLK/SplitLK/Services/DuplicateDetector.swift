import Foundation
import CoreData

/// Compares a newly scanned receipt against the ones already recorded in a
/// group, so the same bill cannot be claimed twice.
///
/// Matching is done on Vision's perceptual fingerprint rather than on the
/// file bytes: the same receipt photographed again is a different file but a
/// near-identical fingerprint, which is exactly the case worth catching.
enum DuplicateDetector {

    struct Match {
        let bill: CDBill
        let distance: Float

        var confidencePercent: Int {
            DuplicateDetector.confidencePercent(for: distance)
        }
    }

    /// A rough confidence for display. The raw distance is unbounded, so this
    /// maps the useful range onto 0-100% rather than claiming precision the
    /// measure does not have.
    static func confidencePercent(for distance: Float) -> Int {
        let scaled = 1 - (Double(distance) / Double(threshold))
        return Int((max(0, min(1, scaled)) * 100).rounded())
    }

    /// Below this distance two receipts are treated as possibly the same bill.
    ///
    /// Tuned against a test set of re-photographed receipts (which score well
    /// under it) and genuinely different receipts from the same restaurant
    /// (which score above it). Deliberately generous: a false warning costs
    /// the user one tap, while a missed duplicate costs somebody money.
    static let threshold: Float = 12.0

    /// The closest prior receipt in the group, if any is close enough to warn about.
    /// Bills are checked newest first so the most recent claim is reported.
    static func findDuplicate(of featurePrint: Data?, in group: CDGroup) -> Match? {
        guard let featurePrint else { return nil }

        var best: Match?

        for bill in group.billList {
            guard let stored = bill.featurePrint,
                  let distance = ReceiptScanner.distance(featurePrint, stored),
                  distance < threshold else { continue }

            if best == nil || distance < best!.distance {
                best = Match(bill: bill, distance: distance)
            }
        }

        return best
    }

    /// Whether two fingerprints are close enough to be the same receipt.
    /// Split out so the threshold logic can be tested without Core Data.
    static func isDuplicate(distance: Float) -> Bool {
        distance < threshold
    }
}
