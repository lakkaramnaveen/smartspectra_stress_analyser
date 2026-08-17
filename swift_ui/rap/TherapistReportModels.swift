import Foundation

// MARK: - Sections

/// What the person can choose to include. This *is* the consent
/// mechanism here — there's no multi-party permission system to build,
/// because there's no second system on the other end to grant access
/// to. The only thing that needs controlling is what goes into the one
/// file that gets created, reviewed, and exported.
enum ReportSection: String, CaseIterable, Identifiable, Sendable {
    case overview
    case stressTrends
    case sleep
    case goals
    case notes

    var id: String { rawValue }

    var label: String {
        switch self {
        case .overview: return "Overview"
        case .stressTrends: return "Stress trends"
        case .sleep: return "Sleep association"
        case .goals: return "Consistency & goals"
        case .notes: return "Your notes"
        }
    }

    var detail: String {
        switch self {
        case .overview: return "Date range and a plain summary of sessions recorded."
        case .stressTrends: return "Weekly average and peak stress across the period."
        case .sleep: return "How logged sleep has related to your stress readings."
        case .goals: return "Streaks and how consistently you've been checking in."
        case .notes: return "Anything you've written yourself for this period, included verbatim."
        }
    }
}

// MARK: - Date Range

enum ReportDateRange: Equatable, Sendable {
    case lastTwoWeeks
    case lastMonth
    case lastThreeMonths
    case custom(start: Date, end: Date)

    func bounds(relativeTo now: Date = Date()) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        switch self {
        case .lastTwoWeeks:
            return (calendar.date(byAdding: .day, value: -14, to: now) ?? now, now)
        case .lastMonth:
            return (calendar.date(byAdding: .month, value: -1, to: now) ?? now, now)
        case .lastThreeMonths:
            return (calendar.date(byAdding: .month, value: -3, to: now) ?? now, now)
        case .custom(let start, let end):
            return (start, end)
        }
    }

    var label: String {
        switch self {
        case .lastTwoWeeks: return "Last 2 weeks"
        case .lastMonth: return "Last month"
        case .lastThreeMonths: return "Last 3 months"
        case .custom: return "Custom range"
        }
    }
}

// MARK: - Config

struct TherapistReportConfig: Equatable, Sendable {
    var dateRange: ReportDateRange = .lastMonth
    var includedSections: Set<ReportSection> = Set(ReportSection.allCases)

    /// Removes the name from the document's header only. Not
    /// anonymization — see the permanent note on `TherapistReportView`
    /// for why that word doesn't really apply to a report meant for
    /// someone who already knows who their own patient is.
    var includeIdentifyingHeader: Bool = true

    /// Optional free text, e.g. "For our check-in on the 14th."
    var providerContext: String = ""
}

// MARK: - Assembled Report

/// The facts a report is built from, before formatting. Kept separate
/// from `TherapistReportRenderer`'s Markdown output the same way
/// `CoachEngine` keeps ranking separate from `CoachTabView`'s
/// presentation — one place computes what's true, another decides how
/// it reads.
struct TherapistReport: Sendable {
    let config: TherapistReportConfig
    let generatedAt: Date
    let profileName: String?

    let sessionCount: Int
    let averageStress: Double?
    let peakStress: Double?
    let weeklyTrend: [WeeklyTrendPoint]

    let sleepAssociation: SleepAssociation?

    let currentStreak: Int
    let bestStreakEver: Int
    let breathingSessionsCompleted: Int

    let notes: [SessionNote]
}
