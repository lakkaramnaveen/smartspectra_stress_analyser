import Foundation
import SwiftUI

// MARK: - Phase

/// Where the user is in the arc from peak back toward their usual range.
enum RecoveryPhase: String, Equatable, Sendable {
    /// Descending, still well above baseline.
    case easing
    /// Approaching the usual range.
    case settling
    /// Back around baseline.
    case settled

    var label: String {
        switch self {
        case .easing: return "Coming down"
        case .settling: return "Settling"
        case .settled: return "Back to your usual range"
        }
    }

    var icon: String {
        switch self {
        case .easing: return "arrow.down.circle"
        case .settling: return "arrow.down.to.line.circle"
        case .settled: return "checkmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .easing: return BrandColor.amber
        case .settling: return BrandColor.lightBlue
        case .settled: return BrandColor.mint
        }
    }
}

// MARK: - Baseline

/// The user's typical resting stress level.
///
/// Recovery is measured against **this**, not a fixed number. People
/// differ, and someone whose ordinary working level sits at 0.45 would
/// otherwise be told they're "still elevated" for an entire session
/// while they get on with their day perfectly fine.
struct StressBaseline: Equatable, Sendable {
    let value: Double
    let sampleCount: Int
    let source: Source

    enum Source: Equatable, Sendable {
        /// Derived from calm stretches earlier in this session.
        case currentSession
        /// Derived from previous recorded sessions.
        case history
        /// Nothing to go on yet — a conservative default.
        case assumed
    }

    /// Fallback when there's no data. Deliberately mid-calm rather than
    /// zero: claiming someone has "recovered" only at a near-zero reading
    /// would mean the state almost never resolves.
    static let assumedDefault = StressBaseline(
        value: 0.30,
        sampleCount: 0,
        source: .assumed
    )

    var isConfident: Bool {
        source != .assumed && sampleCount >= 30
    }
}

// MARK: - State

struct RecoveryState: Equatable, Sendable {
    let phase: RecoveryPhase

    /// Highest reading in the episode being recovered from.
    let peakScore: Double

    /// Latest reading.
    let currentScore: Double

    /// Baseline being measured against.
    let baseline: Double

    /// How far along the descent the user is, 0...1. 0 = at the peak,
    /// 1 = at or below baseline.
    let progress: Double

    /// When the peak occurred.
    let peakAt: Date

    var elapsedSincePeak: TimeInterval {
        Date().timeIntervalSince(peakAt)
    }

    /// Body copy for the panel.
    ///
    /// Observational throughout. Recovery isn't something the user
    /// pulled off — their nervous system did what nervous systems do —
    /// and framing it as an achievement implies the spike was a failure
    /// they've now corrected. That's both inaccurate and a poor thing to
    /// teach someone whose readings spike often.
    var message: String {
        switch phase {
        case .easing:
            return "Your readings are coming down from where they peaked. Nothing to do — this is your system doing its thing."
        case .settling:
            return "Getting close to where you usually sit."
        case .settled:
            return "You're back around your usual range."
        }
    }

    /// Optional secondary line offering something, never instructing.
    var suggestion: String? {
        switch phase {
        case .easing:
            return "A slow breath or two won't hurt if you feel like it."
        case .settling, .settled:
            return nil
        }
    }
}

// MARK: - Configuration

struct RecoveryConfig: Sendable {
    /// Reading that marks the start of a peak episode worth tracking.
    var peakThreshold: Double = 0.75

    /// How far below the peak the reading must fall before recovery is
    /// considered underway. Guards against a single noisy dip being read
    /// as the start of a descent.
    var descentDelta: Double = 0.12

    /// Consecutive descending samples required to confirm a real descent
    /// rather than sensor noise.
    var confirmationSamples: Int = 4

    /// Within this distance of baseline counts as settled.
    var settledTolerance: Double = 0.08

    /// Fraction of the peak-to-baseline gap remaining that flips the
    /// phase from `.easing` to `.settling`.
    var settlingFraction: Double = 0.4

    /// Auto-dismiss the panel this long after reaching `.settled`, so it
    /// doesn't linger once it has nothing left to say.
    var settledDismissDelay: TimeInterval = 20

    /// Don't surface recovery within this window of a breathing session
    /// ending. The user has just come out of a full-screen overlay;
    /// another panel arriving immediately is one interruption too many.
    var postInterventionQuietPeriod: TimeInterval = 45

    /// Minimum gap between recovery panels, so a user oscillating around
    /// the peak threshold isn't shown one repeatedly.
    var cooldown: TimeInterval = 10 * 60

    static let `default` = RecoveryConfig()
}
