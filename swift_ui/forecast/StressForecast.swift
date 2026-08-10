import Foundation
import SwiftUI

// MARK: - Trend Direction

/// Coarse classification of where stress is heading, for UI that needs a
/// glanceable answer rather than a slope value.
enum StressTrendDirection: String, Equatable {
    case rising
    case falling
    case steady
    case insufficientData

    var label: String {
        switch self {
        case .rising: return "Rising"
        case .falling: return "Easing"
        case .steady: return "Steady"
        case .insufficientData: return "Measuring…"
        }
    }

    var icon: String {
        switch self {
        case .rising: return "arrow.up.right"
        case .falling: return "arrow.down.right"
        case .steady: return "arrow.right"
        case .insufficientData: return "hourglass"
        }
    }

    var color: Color {
        switch self {
        case .rising: return BrandColor.amber
        case .falling: return BrandColor.mint
        case .steady: return BrandColor.lightBlue
        case .insufficientData: return BrandColor.mediumGray
        }
    }
}

// MARK: - Forecast

/// The output of `StressTrendAnalyzer`: where stress is now, which way
/// it's moving, how fast, and — if it's climbing — roughly how long
/// until it reaches the intervention threshold.
///
/// `timeToThreshold` is a linear extrapolation of the current trend, not
/// a prediction in any clinical sense. Stress doesn't move in straight
/// lines; this is a "if the last minute continues unchanged" estimate,
/// which is useful for nudging and misleading if treated as fact. UI
/// should present it with hedging language ("~3 min"), never as a
/// countdown.
struct StressForecast: Equatable {
    let currentScore: Double
    let direction: StressTrendDirection

    /// Change in stress score per second. Positive = climbing.
    let slopePerSecond: Double

    /// Goodness-of-fit (R²) of the regression, 0...1. Low values mean the
    /// samples are noisy and the slope shouldn't be trusted.
    let confidence: Double

    /// Seconds until the trend line crosses the intervention threshold.
    /// `nil` when stress isn't rising, the fit is too weak to extrapolate,
    /// or the crossing is too far out to be meaningful.
    let timeToThreshold: TimeInterval?

    /// Number of samples the fit was computed from.
    let sampleCount: Int

    static let empty = StressForecast(
        currentScore: 0,
        direction: .insufficientData,
        slopePerSecond: 0,
        confidence: 0,
        timeToThreshold: nil,
        sampleCount: 0
    )

    /// Human-readable ETA, deliberately rounded and hedged.
    var formattedTimeToThreshold: String? {
        guard let timeToThreshold else { return nil }
        let minutes = Int((timeToThreshold / 60).rounded())
        if minutes < 1 { return "under a minute" }
        if minutes == 1 { return "~1 min" }
        return "~\(minutes) min"
    }

    /// Supportive one-liner for the UI. Phrased as an observation plus an
    /// invitation, not a warning — the reader is by definition already
    /// under load when this matters most.
    var message: String {
        switch direction {
        case .insufficientData:
            return "Gathering enough data to spot trends."
        case .falling:
            return "Your stress is easing. Whatever you're doing is working."
        case .steady:
            return "Holding steady."
        case .rising:
            if let eta = formattedTimeToThreshold {
                return "Stress has been climbing — on this trend you'd hit your threshold in \(eta). Good moment for a breath."
            }
            return "Stress has been climbing gently."
        }
    }
}
