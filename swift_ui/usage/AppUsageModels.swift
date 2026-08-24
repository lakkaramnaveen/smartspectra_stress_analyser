import Foundation

// MARK: - Focus Session

/// One continuous stretch a single app spent frontmost.
///
/// Deliberately this narrow: an app identity plus a start and end time.
/// Nothing about window titles, documents, URLs, or message content is
/// captured here — not because of a policy choice this struct enforces,
/// but because `NSWorkspace`'s public app-activation API literally
/// cannot see any of that. There's no deeper layer being deliberately
/// left out; this is everything the underlying API exposes.
struct AppFocusSession: Codable, Equatable, Sendable, Identifiable {
    var id: String { "\(bundleID)-\(start.timeIntervalSince1970)" }
    let bundleID: String
    let appName: String
    let start: Date
    let end: Date

    var duration: TimeInterval { end.timeIntervalSince(start) }
}

// MARK: - Persisted State

struct AppUsageState: Codable, Equatable, Sendable {
    var sessions: [AppFocusSession]
    /// Off by default — see the design note on `AppUsageCoordinator`.
    var isEnabled: Bool

    static let initial = AppUsageState(sessions: [], isEnabled: false)
}

// MARK: - Association

/// How one app's average stress reading compared to the person's
/// overall baseline while it was frontmost.
///
/// An association, not a cause. "Stress ran higher while Mail was
/// frontmost" doesn't distinguish between Mail causing that, the person
/// opening Mail *because* something else had already raised their
/// stress, or both reflecting a third thing entirely (a demanding
/// morning that involved both). `AppStressAnalyzer`'s doc comment goes
/// into this further; the type itself just carries the numbers.
struct AppStressAssociation: Identifiable, Sendable {
    var id: String { bundleID }
    let bundleID: String
    let appName: String
    let sessionCount: Int
    let totalMinutes: Double
    let averageStressDuringApp: Double
    let overallAverageStress: Double
    let deltaPoints: Double
    /// Reuses `CoachConfidence` rather than a near-identical new enum —
    /// both features gate on small counts of real-world events (an
    /// intervention used a handful of times; an app frontmost a handful
    /// of times), so the same three tiers and the same thresholds apply.
    let confidence: CoachConfidence
}
