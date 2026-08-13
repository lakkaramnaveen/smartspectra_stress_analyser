import Foundation
import SwiftUI

// MARK: - Signal Quality

/// How much the current gaze feed can be trusted.
///
/// Every ergonomics claim is gated on this. Gaze confidence in this app
/// is derived rather than native — the SmartSpectra SDK doesn't expose
/// eye tracking directly — so it degrades badly with poor lighting,
/// off-angle faces, or the user leaving the frame. Reporting "you've
/// been looking down for 20 minutes" when the tracker actually lost the
/// face 20 minutes ago is the failure mode this exists to prevent.
enum GazeSignalQuality: Equatable, Sendable {
    case good        // confident enough to make claims
    case marginal    // show data, hedge the wording
    case unusable    // show nothing but a "can't tell" state

    static func classify(_ confidence: Double) -> GazeSignalQuality {
        switch confidence {
        case 0.65...: return .good
        case 0.35..<0.65: return .marginal
        default: return .unusable
        }
    }

    var label: String {
        switch self {
        case .good: return "Tracking well"
        case .marginal: return "Tracking is patchy"
        case .unusable: return "Can't see you clearly"
        }
    }

    var color: Color {
        switch self {
        case .good: return BrandColor.mint
        case .marginal: return BrandColor.amber
        case .unusable: return BrandColor.mediumGray
        }
    }
}

// MARK: - Baseline

/// Reference gaze position captured at the start of a session.
///
/// Everything vertical is measured **relative to this**, never against an
/// absolute "correct" value. There is no universal correct gaze Y: it
/// depends on camera height, screen size, desk depth, and how tall the
/// person is. A baseline turns an unusable absolute reading into a
/// usable relative one — "lower than where you started" is a claim the
/// data supports; "too low" is not.
struct GazeBaseline: Equatable, Sendable {
    let verticalCentre: Double
    let capturedAt: Date
    let sampleCount: Int

    /// Samples needed before a baseline is considered established.
    static let requiredSamples = 30
}

// MARK: - Nudge

/// A reminder surfaced to the user.
///
/// Called nudges, not alerts, throughout — these are low-stakes
/// suggestions about habits, and dressing them up as alerts would give
/// them an urgency they don't have.
struct ErgonomicsNudge: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// Continuous screen time without a break.
        case screenBreak(minutes: Int)
        /// Sustained downward gaze.
        case neckFlexion(minutes: Int)
        /// Gaze centre has drifted below the session baseline.
        case downwardDrift
        /// Long stretch without a distance change (20-20-20 style).
        case eyeRest
    }

    let id = UUID()
    let kind: Kind
    let title: String
    let body: String
    let raisedAt: Date

    var icon: String {
        switch kind {
        case .screenBreak: return "figure.walk"
        case .neckFlexion: return "figure.stand"
        case .downwardDrift: return "arrow.down.circle"
        case .eyeRest: return "eye"
        }
    }

    static func == (lhs: ErgonomicsNudge, rhs: ErgonomicsNudge) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Session Stats

/// Rolling ergonomics picture for the current sitting.
struct ErgonomicsStats: Equatable, Sendable {
    /// Time since the session started.
    var screenTimeSeconds: TimeInterval = 0

    /// Time since the last acknowledged break.
    var timeSinceBreakSeconds: TimeInterval = 0

    /// Cumulative time with gaze below the baseline threshold.
    var downwardGazeSeconds: TimeInterval = 0

    /// Longest single unbroken downward stretch.
    var longestDownwardStretchSeconds: TimeInterval = 0

    /// Breaks the user marked as taken.
    var breaksTaken: Int = 0

    /// Current gaze offset from baseline. Negative = higher in frame,
    /// positive = lower. Nil until a baseline exists.
    var driftFromBaseline: Double?

    var quality: GazeSignalQuality = .unusable

    /// Share of the session spent looking down. Only meaningful with a
    /// decent amount of tracked time behind it.
    var downwardShare: Double {
        guard screenTimeSeconds > 60 else { return 0 }
        return min(downwardGazeSeconds / screenTimeSeconds, 1)
    }

    static let empty = ErgonomicsStats()
}

// MARK: - Configuration

struct ErgonomicsConfig: Codable, Equatable, Sendable {
    /// Minutes of continuous screen time before a break nudge.
    ///
    /// 50 minutes rather than a rounder number: long enough not to
    /// interrupt real work, short enough to land inside a typical
    /// hour-long block. This is a habit heuristic, not a clinical
    /// figure — no specific interval has strong evidence behind it.
    var screenBreakMinutes: Int = 50

    /// Minutes of *cumulative* downward gaze before a neck nudge.
    var neckFlexionMinutes: Int = 20

    /// Minutes between eye-rest reminders. Loosely modelled on the
    /// commonly-repeated 20-20-20 guidance (every 20 minutes, look at
    /// something 20 feet away for 20 seconds), which is widely
    /// recommended by optometry bodies though the specific numbers are
    /// convention rather than trial-derived.
    var eyeRestMinutes: Int = 20

    /// How far below baseline counts as "looking down", in normalised
    /// gaze units. Roughly a tenth of the frame height.
    var downwardThreshold: Double = 0.10

    /// Minimum gap between nudges of any kind.
    var nudgeCooldownMinutes: Int = 5

    var isEnabled: Bool = true
    var eyeRestEnabled: Bool = true

    static let `default` = ErgonomicsConfig()

    static let screenBreakRange = 20...120
    static let neckFlexionRange = 10...60
    static let eyeRestRange = 10...60
}
