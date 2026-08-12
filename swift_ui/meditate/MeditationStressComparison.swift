import Foundation
import SwiftUI

// MARK: - Result

/// Before/after stress comparison for a completed meditation.
///
/// Reported as an **observation about a single sitting**, never as a
/// measured effect of the meditation. The distinction is not pedantry:
///
/// - Sitting still for ten minutes lowers stress markers on its own,
///   independent of anything meditative.
/// - Regression to the mean means a session begun while stressed will
///   very often end lower whatever happens in between.
/// - A single before/after pair has no control and n=1.
///
/// Presenting that as "meditation reduced your stress 34%" teaches a
/// causal story the data can't support — and sets up the inverse failure
/// where a user sees an increase and concludes they meditated wrong.
struct MeditationStressComparison: Equatable, Sendable {

    enum Direction: Equatable, Sendable {
        case lower
        case higher
        case unchanged
        /// Too few samples to say anything.
        case insufficientData
    }

    let before: Double?
    let after: Double?
    let sampleCount: Int
    let direction: Direction

    /// Absolute change in stress-score points (not a percentage of the
    /// starting value — a change from 0.10 to 0.05 is 5 points, not a
    /// dramatic-sounding "50% reduction").
    let deltaPoints: Double?

    /// Minimum samples on each side before a comparison is offered.
    static let minimumSamplesPerSide = 8

    /// Change smaller than this is reported as unchanged. Physiological
    /// signals wander; a 2-point difference is noise.
    static let meaningfulDelta = 0.05

    static let noData = MeditationStressComparison(
        before: nil,
        after: nil,
        sampleCount: 0,
        direction: .insufficientData,
        deltaPoints: nil
    )

    /// Headline. Describes the sitting, not a causal effect.
    var headline: String {
        switch direction {
        case .insufficientData:
            return "Not enough readings to compare"
        case .unchanged:
            return "Your stress readings held steady"
        case .lower:
            return "Your stress readings ended lower than they started"
        case .higher:
            return "Your stress readings ended higher than they started"
        }
    }

    var detail: String? {
        guard let before, let after, let deltaPoints, direction != .insufficientData else {
            return nil
        }

        let beforeText = String(format: "%.0f%%", before * 100)
        let afterText = String(format: "%.0f%%", after * 100)

        switch direction {
        case .unchanged:
            return "\(beforeText) at the start, \(afterText) at the end."
        case .lower, .higher:
            let points = String(format: "%.0f", abs(deltaPoints) * 100)
            return "\(beforeText) at the start, \(afterText) at the end — \(points) points \(direction == .lower ? "lower" : "higher")."
        case .insufficientData:
            return nil
        }
    }

    /// Always shown alongside a comparison. One sentence, stated plainly.
    var caveat: String {
        switch direction {
        case .insufficientData:
            return "Monitoring wasn't running for long enough during this session."
        case .higher:
            return "Readings move for all sorts of reasons, and a higher number doesn't mean you did anything wrong."
        case .lower, .unchanged:
            return "This is one sitting, and readings drift on their own — it's a snapshot, not a measure of how well it worked."
        }
    }

    var directionColor: Color {
        switch direction {
        case .lower: return BrandColor.mint
        // Deliberately not coral. A higher reading isn't a failure, and
        // colouring it as an error would frame it as one.
        case .higher: return BrandColor.lightBlue
        case .unchanged: return BrandColor.lightBlue
        case .insufficientData: return BrandColor.mediumGray
        }
    }
}

// MARK: - Analyzer

/// Computes the before/after comparison from stress samples collected
/// during a meditation.
///
/// Pure and UI-free — same shape as `StressScoringEngine` and
/// `CorrelationAnalyzer`.
struct MeditationStressAnalyzer: Sendable {

    /// Fraction of the session used for each comparison window. A fifth
    /// at each end, so a 5-minute meditation compares its first minute
    /// against its last.
    let windowFraction: Double

    init(windowFraction: Double = 0.2) {
        self.windowFraction = windowFraction
    }

    func compare(samples: [Double]) -> MeditationStressComparison {
        let windowSize = max(
            MeditationStressComparison.minimumSamplesPerSide,
            Int(Double(samples.count) * windowFraction)
        )

        guard samples.count >= windowSize * 2 else {
            return MeditationStressComparison(
                before: nil,
                after: nil,
                sampleCount: samples.count,
                direction: .insufficientData,
                deltaPoints: nil
            )
        }

        let before = Array(samples.prefix(windowSize)).average
        let after = Array(samples.suffix(windowSize)).average
        let delta = after - before

        let direction: MeditationStressComparison.Direction
        if abs(delta) < MeditationStressComparison.meaningfulDelta {
            direction = .unchanged
        } else {
            direction = delta < 0 ? .lower : .higher
        }

        return MeditationStressComparison(
            before: before,
            after: after,
            sampleCount: samples.count,
            direction: direction,
            deltaPoints: delta
        )
    }
}
