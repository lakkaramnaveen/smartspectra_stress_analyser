import Foundation
import SwiftUI

// MARK: - Category

enum InsightCategory: String, CaseIterable, Sendable {
    case timeOfDay
    case dayOfWeek
    case correlation
    case leadIndicator
    case trend

    var label: String {
        switch self {
        case .timeOfDay: return "Time of Day"
        case .dayOfWeek: return "Weekly Rhythm"
        case .correlation: return "Vital Signs"
        case .leadIndicator: return "Early Signals"
        case .trend: return "Progress"
        }
    }

    var icon: String {
        switch self {
        case .timeOfDay: return "clock"
        case .dayOfWeek: return "calendar"
        case .correlation: return "arrow.triangle.branch"
        case .leadIndicator: return "bolt.horizontal"
        case .trend: return "chart.xyaxis.line"
        }
    }

    var color: Color {
        switch self {
        case .timeOfDay: return BrandColor.lightBlue
        case .dayOfWeek: return BrandColor.teal
        case .correlation: return BrandColor.mint
        case .leadIndicator: return BrandColor.amber
        case .trend: return BrandColor.primaryBlue
        }
    }
}

// MARK: - Confidence

/// How much weight a reader should put on an insight.
///
/// Exposed in the UI on every card, deliberately. A pattern drawn from
/// five sessions and one drawn from eighty look identical once they're
/// rendered as a confident sentence, and that similarity is misleading.
/// Showing the tier — and the sample count behind it — lets someone
/// calibrate rather than take every observation at face value.
enum InsightConfidence: Int, Comparable, Sendable {
    case exploratory = 0   // suggestive; could easily be noise
    case moderate = 1      // holds up across a reasonable spread of data
    case strong = 2        // consistent across many sessions and days

    var label: String {
        switch self {
        case .exploratory: return "Early signal"
        case .moderate: return "Likely"
        case .strong: return "Consistent"
        }
    }

    var color: Color {
        switch self {
        case .exploratory: return BrandColor.mediumGray
        case .moderate: return BrandColor.lightBlue
        case .strong: return BrandColor.mint
        }
    }

    static func < (lhs: InsightConfidence, rhs: InsightConfidence) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Insight

/// A single observation derived from session history.
struct Insight: Identifiable, Sendable {
    let id = UUID()
    let category: InsightCategory
    let confidence: InsightConfidence

    /// One-line summary. Phrased as an observation, never an instruction.
    let headline: String

    /// Supporting sentence with the actual numbers behind the headline.
    let detail: String

    /// How many sessions contributed. Surfaced in the UI so the reader
    /// can judge the claim for themselves.
    let sessionCount: Int

    /// Optional practical suggestion. Kept separate from `detail` so the
    /// observation and the advice are visually distinct — the first is
    /// data, the second is opinion.
    let suggestion: String?
}

// MARK: - Aggregates

/// Mean stress within one hour-of-day bucket, across all sessions.
struct HourBucket: Identifiable, Sendable {
    var id: Int { hour }
    let hour: Int              // 0...23
    let averageStress: Double
    let sampleCount: Int
    let distinctDays: Int      // how many separate calendar days contributed
}

/// Mean stress for one weekday, across all sessions.
struct WeekdayBucket: Identifiable, Sendable {
    var id: Int { weekday }
    let weekday: Int           // 1 = Sunday, per Calendar
    let averageStress: Double
    let sessionCount: Int

    var shortName: String {
        Calendar.current.shortWeekdaySymbols[safe: weekday - 1] ?? "?"
    }
}

/// Week-over-week summary for the trend chart.
struct WeeklyTrendPoint: Identifiable, Sendable {
    var id: Date { weekStart }
    let weekStart: Date
    let averageStress: Double
    let peakStress: Double
    let sessionCount: Int
}

/// Everything the generator needs, computed once from raw recordings.
struct InsightAggregates: Sendable {
    let hourBuckets: [HourBucket]
    let weekdayBuckets: [WeekdayBucket]
    let weeklyTrend: [WeeklyTrendPoint]
    let totalSessions: Int
    let totalSnapshots: Int
    let distinctDays: Int

    /// Pearson r between each vital and stress, across all snapshots.
    let heartRateCorrelation: Double?
    let breathingCorrelation: Double?
    let edaCorrelation: Double?

    /// Best lead-lag result for EDA against stress: how many seconds EDA
    /// tends to move *before* stress does, and how strong that is.
    let edaLeadSeconds: Double?
    let edaLeadStrength: Double?

    static let empty = InsightAggregates(
        hourBuckets: [],
        weekdayBuckets: [],
        weeklyTrend: [],
        totalSessions: 0,
        totalSnapshots: 0,
        distinctDays: 0,
        heartRateCorrelation: nil,
        breathingCorrelation: nil,
        edaCorrelation: nil,
        edaLeadSeconds: nil,
        edaLeadStrength: nil
    )
}

// MARK: - Helpers

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
