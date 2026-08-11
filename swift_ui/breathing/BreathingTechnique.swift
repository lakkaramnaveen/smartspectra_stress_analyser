import Foundation
import SwiftUI

// MARK: - Phase

enum BreathPhase: String, Codable, Equatable, Sendable, CaseIterable {
    case inhale
    case holdIn
    case exhale
    case holdOut

    var instruction: String {
        switch self {
        case .inhale: return "Breathe in"
        case .holdIn: return "Hold"
        case .exhale: return "Breathe out"
        case .holdOut: return "Rest"
        }
    }

    /// Orb scale target for this phase. Holds keep the previous scale so
    /// the visual matches what the body is doing — expanded during a
    /// held inhale, contracted during a held exhale.
    var orbScale: CGFloat {
        switch self {
        case .inhale, .holdIn: return 1.20
        case .exhale, .holdOut: return 0.55
        }
    }

    var orbOpacity: Double {
        switch self {
        case .inhale, .holdIn: return 1.0
        case .exhale, .holdOut: return 0.35
        }
    }
}

// MARK: - Pattern

/// Durations for one full breath cycle. Zero-length phases are skipped
/// by the engine, which is how two-phase techniques (coherent breathing)
/// and four-phase ones (box breathing) share a single model.
struct BreathingPattern: Codable, Equatable, Sendable {
    var inhale: TimeInterval
    var holdIn: TimeInterval
    var exhale: TimeInterval
    var holdOut: TimeInterval

    var cycleDuration: TimeInterval {
        inhale + holdIn + exhale + holdOut
    }

    /// Phases in order, with zero-length ones omitted.
    var activePhases: [(phase: BreathPhase, duration: TimeInterval)] {
        [
            (.inhale, inhale),
            (.holdIn, holdIn),
            (.exhale, exhale),
            (.holdOut, holdOut)
        ].filter { $0.duration > 0 }
    }

    /// Compact notation, e.g. "4–7–8" or "5.5–5.5".
    var notation: String {
        activePhases
            .map { formatSeconds($0.duration) }
            .joined(separator: "–")
    }

    private func formatSeconds(_ value: TimeInterval) -> String {
        value == value.rounded()
            ? String(Int(value))
            : String(format: "%.1f", value)
    }
}

// MARK: - Safe Ranges

/// Bounds applied to user-authored patterns.
///
/// Breath work isn't inert. Extended retention reliably produces
/// lightheadedness, and very short, fast cycles can shade into
/// hyperventilation. None of the established techniques come close to
/// these limits — 4-7-8's seven-second hold sits well inside them — so
/// the clamps cost nothing in practice and only prevent someone
/// assembling a 45-second breath hold in a UI that gave no indication
/// that was a meaningfully different thing to do.
enum BreathingLimits {
    static let inhaleRange: ClosedRange<TimeInterval> = 2...12
    static let holdRange: ClosedRange<TimeInterval> = 0...10
    static let exhaleRange: ClosedRange<TimeInterval> = 2...15
    static let cycleCountRange: ClosedRange<Int> = 3...20

    static func clamp(_ pattern: BreathingPattern) -> BreathingPattern {
        BreathingPattern(
            inhale: pattern.inhale.clamped(to: inhaleRange),
            holdIn: pattern.holdIn.clamped(to: holdRange),
            exhale: pattern.exhale.clamped(to: exhaleRange),
            holdOut: pattern.holdOut.clamped(to: holdRange)
        )
    }
}

// MARK: - Technique

struct BreathingTechnique: Identifiable, Codable, Equatable, Sendable {
    let id: String              // stable string ID; survives catalog edits
    var name: String
    var summary: String
    var pattern: BreathingPattern
    var cycleCount: Int
    var isBuiltIn: Bool

    var totalDuration: TimeInterval {
        pattern.cycleDuration * Double(cycleCount)
    }

    /// Applies safe bounds. Called on save and before a session starts,
    /// so a pattern decoded from an older or hand-edited file can't
    /// bypass the limits.
    var sanitized: BreathingTechnique {
        var copy = self
        copy.pattern = BreathingLimits.clamp(pattern)
        copy.cycleCount = cycleCount.clamped(to: BreathingLimits.cycleCountRange)
        return copy
    }
}

// MARK: - Built-In Catalog

extension BreathingTechnique {

    /// 4-7-8. Long exhale relative to inhale, which is the mechanism —
    /// extended exhalation is what shifts autonomic balance, not the
    /// hold on its own.
    static let fourSevenEight = BreathingTechnique(
        id: "builtin.478",
        name: "4-7-8",
        summary: "Four in, seven hold, eight out. The long exhale is the active ingredient — good for winding down.",
        pattern: BreathingPattern(inhale: 4, holdIn: 7, exhale: 8, holdOut: 0),
        cycleCount: 4,
        isBuiltIn: true
    )

    /// Box breathing. Even four-part rhythm.
    static let box = BreathingTechnique(
        id: "builtin.box",
        name: "Box breathing",
        summary: "Equal counts on all four sides. Steady and easy to keep track of — useful when you need to settle without slowing down.",
        pattern: BreathingPattern(inhale: 4, holdIn: 4, exhale: 4, holdOut: 4),
        cycleCount: 6,
        isBuiltIn: true
    )

    /// Coherent breathing. No holds; roughly 5.5 breaths per minute.
    static let coherent = BreathingTechnique(
        id: "builtin.coherent",
        name: "Coherent breathing",
        summary: "Five and a half seconds each way, no holds. The gentlest option, and the easiest to sustain for longer.",
        pattern: BreathingPattern(inhale: 5.5, holdIn: 0, exhale: 5.5, holdOut: 0),
        cycleCount: 8,
        isBuiltIn: true
    )

    /// The app's original pattern, kept so existing users' muscle memory
    /// still has a home.
    static let extendedExhale = BreathingTechnique(
        id: "builtin.4-6",
        name: "Extended exhale",
        summary: "Four in, six out. Simple, no holds — a good default if you're new to this.",
        pattern: BreathingPattern(inhale: 4, holdIn: 0, exhale: 6, holdOut: 0),
        cycleCount: 6,
        isBuiltIn: true
    )

    static let builtIn: [BreathingTechnique] = [
        .extendedExhale,
        .coherent,
        .box,
        .fourSevenEight
    ]

    /// Template used when the user creates a custom technique.
    static func newCustom() -> BreathingTechnique {
        BreathingTechnique(
            id: "custom.\(UUID().uuidString)",
            name: "My technique",
            summary: "",
            pattern: BreathingPattern(inhale: 4, holdIn: 0, exhale: 6, holdOut: 0),
            cycleCount: 6,
            isBuiltIn: false
        )
    }
}

// MARK: - Completion Tracking

struct TechniqueCompletion: Codable, Equatable, Sendable {
    var techniqueID: String
    var completedCount: Int
    var lastCompletedAt: Date?
}

/// Persisted breathing state: which technique is selected, any custom
/// ones, and per-technique completion counts.
struct BreathingPreferences: Codable, Equatable, Sendable {
    var selectedTechniqueID: String
    var customTechniques: [BreathingTechnique]
    var completions: [TechniqueCompletion]

    static let initial = BreathingPreferences(
        selectedTechniqueID: BreathingTechnique.extendedExhale.id,
        customTechniques: [],
        completions: []
    )

    func completionCount(for id: String) -> Int {
        completions.first { $0.techniqueID == id }?.completedCount ?? 0
    }

    var totalCompletions: Int {
        completions.reduce(0) { $0 + $1.completedCount }
    }
}

// MARK: - Helpers

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
