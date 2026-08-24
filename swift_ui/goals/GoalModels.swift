import Foundation
import SwiftUI

// MARK: - Goal Kind

/// What a goal actually measures.
///
/// Deliberately weighted toward *process* over *outcome*. A goal like
/// "record a session today" is fully within the user's control; a goal
/// like "keep peak stress under 40%" is only partly so — stress responds
/// to a bad meeting, a poor night's sleep, and a dozen things the user
/// didn't choose. Rewarding only outcomes means punishing people for
/// hard days, which is both unfair and counterproductive for the thing
/// the app is trying to support.
///
/// Outcome goals still exist (they're motivating when they land), but
/// they're the minority, they're never streak-bearing, and they're
/// phrased as personal bests rather than pass/fail.
enum GoalKind: Codable, Equatable, Sendable {

    // MARK: Process goals — fully within the user's control

    /// Record any session of at least this length.
    case completeSession(minimumSeconds: TimeInterval)

    /// Finish this many guided breathing interventions.
    case completeBreathing(count: Int)

    /// Record a session on this many separate days in a week.
    case activeDays(count: Int)

    // MARK: Outcome goals — partly outside the user's control

    /// Hold below the calm threshold continuously for this long.
    case sustainedCalm(seconds: TimeInterval)

    /// Return from a stress peak back below the calm threshold within
    /// this many seconds.
    case fastRecovery(withinSeconds: TimeInterval)

    /// True when this goal's outcome is substantially outside the user's
    /// direct control. Used by the UI to soften framing, and by the
    /// streak calculator to exclude these from streak eligibility —
    /// a streak should never depend on having a good day.
    var isOutcomeBased: Bool {
        switch self {
        case .completeSession, .completeBreathing, .activeDays:
            return false
        case .sustainedCalm, .fastRecovery:
            return true
        }
    }

    var icon: String {
        switch self {
        case .completeSession: return "record.circle"
        case .completeBreathing: return "wind"
        case .activeDays: return "calendar"
        case .sustainedCalm: return "leaf.fill"
        case .fastRecovery: return "arrow.uturn.down.circle"
        }
    }
}

// MARK: - Goal

struct Goal: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let kind: GoalKind
    let title: String
    let subtitle: String
    /// Whether the user has this goal switched on.
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        kind: GoalKind,
        title: String,
        subtitle: String,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.isEnabled = isEnabled
    }
}

// MARK: - Goal Progress

struct GoalProgress: Identifiable, Sendable {
    var id: UUID { goal.id }
    let goal: Goal
    /// 0...1. Clamped — overshooting a goal doesn't produce >1.
    let fraction: Double
    /// Human-readable current state, e.g. "3 of 5 days".
    let statusText: String
    var isComplete: Bool { fraction >= 1.0 }
}

// MARK: - Achievement

enum AchievementTier: Int, Codable, Comparable, Sendable {
    case bronze = 0, silver = 1, gold = 2

    var label: String {
        switch self {
        case .bronze: return "Bronze"
        case .silver: return "Silver"
        case .gold: return "Gold"
        }
    }

    var color: Color {
        switch self {
        case .bronze: return Color(red: 0.80, green: 0.55, blue: 0.35)
        case .silver: return Color(red: 0.72, green: 0.75, blue: 0.80)
        case .gold: return BrandColor.amber
        }
    }

    static func < (lhs: AchievementTier, rhs: AchievementTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A milestone definition. Immutable; whether it's *unlocked* is tracked
/// separately in `UnlockedAchievement`.
struct Achievement: Identifiable, Codable, Equatable, Sendable {
    let id: String          // stable string ID so unlocks survive edits
    let title: String
    let detail: String
    let icon: String
    let tier: AchievementTier
}

struct UnlockedAchievement: Identifiable, Codable, Equatable, Sendable {
    var id: String { achievementID }
    let achievementID: String
    let unlockedAt: Date
}

// MARK: - Streak

/// Current and best streak of qualifying days.
///
/// `graceDaysRemaining` is the forgiveness mechanism: a single missed day
/// doesn't end a streak. This isn't a gimmick — an unforgiving streak on
/// a *stress* app creates exactly the pressure the app exists to reduce,
/// and the most common way people quit wellness tools is breaking a long
/// chain and feeling there's nothing left to protect.
struct StreakState: Codable, Equatable, Sendable {
    var current: Int
    var best: Int
    var lastQualifyingDay: Date?
    var graceDaysRemaining: Int

    static let empty = StreakState(
        current: 0,
        best: 0,
        lastQualifyingDay: nil,
        graceDaysRemaining: 1
    )

    /// Copy phrased without loss framing. "You lost your 12-day streak"
    /// is accurate and demoralising; the goal is to make returning feel
    /// low-stakes rather than to punish absence.
    var encouragement: String {
        switch current {
        case 0: return "Starting fresh — every session counts."
        case 1: return "First day in. Nice."
        case 2...6: return "\(current) days running."
        case 7...20: return "\(current) days — this is becoming a habit."
        default: return "\(current) days. Genuinely impressive consistency."
        }
    }
}

// MARK: - Personal Records

/// Personal bests. Framed as records rather than targets — a user who
/// treats "lowest peak stress ever" as a bar to clear every session has
/// turned a memento into a source of pressure, so the UI presents these
/// as history, never as something to beat.
struct PersonalRecords: Codable, Equatable, Sendable {
    var longestCalmRunSeconds: TimeInterval?
    var lowestSessionPeakStress: Double?
    var fastestRecoverySeconds: TimeInterval?
    var longestDayStreak: Int
    var totalSessions: Int
    var totalBreathingCompleted: Int

    static let empty = PersonalRecords(
        longestCalmRunSeconds: nil,
        lowestSessionPeakStress: nil,
        fastestRecoverySeconds: nil,
        longestDayStreak: 0,
        totalSessions: 0,
        totalBreathingCompleted: 0
    )
}

// MARK: - Aggregate state

/// Everything the goals feature persists, in one Codable blob.
struct GoalsState: Codable, Equatable, Sendable {
    var goals: [Goal]
    var unlocked: [UnlockedAchievement]
    var streak: StreakState
    var records: PersonalRecords

    static let initial = GoalsState(
        goals: Goal.defaultGoals,
        unlocked: [],
        streak: .empty,
        records: .empty
    )
}

// MARK: - Default Goals

extension Goal {
    /// Starting set. Three process goals to one outcome goal, by design —
    /// see the note on `GoalKind`.
    static let defaultGoals: [Goal] = [
        Goal(
            kind: .completeSession(minimumSeconds: 300),
            title: "Check in",
            subtitle: "Record a session of 5 minutes or more"
        ),
        Goal(
            kind: .activeDays(count: 4),
            title: "Four days this week",
            subtitle: "Show up on four separate days"
        ),
        Goal(
            kind: .completeBreathing(count: 1),
            title: "One breathing break",
            subtitle: "Complete a guided breathing exercise"
        ),
        Goal(
            kind: .sustainedCalm(seconds: 300),
            title: "Five calm minutes",
            subtitle: "Hold below your calm threshold for five minutes straight"
        )
    ]
}
