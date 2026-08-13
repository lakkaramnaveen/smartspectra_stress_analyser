import Foundation
import SwiftUI

// MARK: - Quality

/// Subjective rest quality.
///
/// Deliberately coarse and worded around *how you feel*, not how well you
/// slept. People are poor at estimating sleep quality but reasonable at
/// reporting how rested they feel, and the latter is what actually
/// relates to the day ahead.
///
/// There is no "bad" option by that name. A tracker that labels nights as
/// failures is one people start avoiding on exactly the mornings the data
/// would be most interesting.
enum RestQuality: Int, Codable, CaseIterable, Sendable, Comparable {
    case rough = 0
    case okay = 1
    case good = 2
    case excellent = 3

    var label: String {
        switch self {
        case .rough: return "Rough"
        case .okay: return "Okay"
        case .good: return "Good"
        case .excellent: return "Really good"
        }
    }

    var icon: String {
        switch self {
        case .rough: return "cloud.rain"
        case .okay: return "cloud"
        case .good: return "sun.haze"
        case .excellent: return "sun.max"
        }
    }

    var color: Color {
        switch self {
        case .rough: return BrandColor.mediumGray
        case .okay: return BrandColor.lightBlue
        case .good: return BrandColor.teal
        case .excellent: return BrandColor.mint
        }
    }

    static func < (lhs: RestQuality, rhs: RestQuality) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Entry

/// One night, logged by the user.
struct SleepEntry: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    /// The day this night's sleep *precedes* — i.e. the morning it was
    /// logged for. Normalised to start-of-day so it joins cleanly against
    /// session data.
    let forDay: Date
    let hours: Double
    let quality: RestQuality
    let loggedAt: Date

    init(
        id: UUID = UUID(),
        forDay: Date,
        hours: Double,
        quality: RestQuality,
        loggedAt: Date = Date()
    ) {
        self.id = id
        self.forDay = Calendar.current.startOfDay(for: forDay)
        self.hours = hours
        self.quality = quality
        self.loggedAt = loggedAt
    }

    /// Plausible range for the slider. Values outside this are almost
    /// certainly mis-entries rather than real nights.
    static let hoursRange: ClosedRange<Double> = 3...12
}

// MARK: - Association

/// What, if anything, the user's own data suggests about the relationship
/// between rest and their stress readings.
///
/// Framed as an association across nights, never as a causal effect and
/// never as a percentage of a baseline. Three reasons the stronger
/// framing would be wrong:
///
///  - Self-reported hours are a rough estimate, not a measurement.
///  - The sample is a handful of nights, with no control.
///  - Causality plausibly runs both ways: a demanding week produces both
///    poor sleep and elevated readings, with neither causing the other.
struct SleepAssociation: Equatable, Sendable {

    enum Direction: Equatable, Sendable {
        /// Shorter/poorer nights tended to precede higher readings.
        case restRelatesToLowerStress
        /// The opposite, which does happen and isn't a data error.
        case restRelatesToHigherStress
        /// No relationship worth mentioning.
        case noClearPattern
        /// Not enough logged nights yet.
        case insufficientData
    }

    let direction: Direction
    let nightsCompared: Int

    /// Correlation coefficient between rest and mean daily stress.
    let coefficient: Double?

    /// Mean stress on the third of days following the *most* rest.
    let stressAfterBestRest: Double?
    /// Mean stress on the third following the *least* rest.
    let stressAfterLeastRest: Double?

    /// Nights needed before anything is reported.
    static let minimumNights = 10

    /// |r| below this is treated as no pattern.
    static let minimumCoefficient = 0.30

    static let none = SleepAssociation(
        direction: .insufficientData,
        nightsCompared: 0,
        coefficient: nil,
        stressAfterBestRest: nil,
        stressAfterLeastRest: nil
    )

    var headline: String {
        switch direction {
        case .insufficientData:
            return "Not enough nights logged yet"
        case .noClearPattern:
            return "No clear pattern between your rest and your readings"
        case .restRelatesToLowerStress:
            return "Better-rested days have tended to run calmer"
        case .restRelatesToHigherStress:
            return "Better-rested days have tended to run higher"
        }
    }

    var detail: String? {
        guard direction == .restRelatesToLowerStress || direction == .restRelatesToHigherStress,
              let best = stressAfterBestRest,
              let least = stressAfterLeastRest else {
            return nil
        }

        let bestText = String(format: "%.0f%%", best * 100)
        let leastText = String(format: "%.0f%%", least * 100)

        return "Across \(nightsCompared) nights, average stress was \(bestText) after your most restful nights and \(leastText) after your least."
    }

    /// Always shown with any result. The caveat and the finding belong in
    /// the same glance — one tucked behind a disclosure is one nobody
    /// reads.
    var caveat: String {
        switch direction {
        case .insufficientData:
            return "Log a few more mornings and there'll be enough to look at."
        case .noClearPattern:
            return "That's a normal result, and a common one — plenty of things move these readings."
        case .restRelatesToLowerStress, .restRelatesToHigherStress:
            return "These two things moved together across \(nightsCompared) nights. That's not the same as one causing the other — a demanding week can easily produce both."
        }
    }

    var color: Color {
        switch direction {
        case .restRelatesToLowerStress: return BrandColor.mint
        case .restRelatesToHigherStress: return BrandColor.lightBlue
        case .noClearPattern: return BrandColor.lightBlue
        case .insufficientData: return BrandColor.mediumGray
        }
    }
}

// MARK: - Time-of-day comparison

/// Morning vs. afternoon vs. evening averages, drawn from session data.
struct DaypartStress: Identifiable, Equatable, Sendable {
    enum Daypart: String, CaseIterable, Sendable {
        case morning, afternoon, evening

        var label: String {
            switch self {
            case .morning: return "Morning"
            case .afternoon: return "Afternoon"
            case .evening: return "Evening"
            }
        }

        var hourRange: Range<Int> {
            switch self {
            case .morning: return 5..<12
            case .afternoon: return 12..<18
            case .evening: return 18..<24
            }
        }

        var icon: String {
            switch self {
            case .morning: return "sunrise"
            case .afternoon: return "sun.max"
            case .evening: return "moon.stars"
            }
        }
    }

    var id: String { part.rawValue }
    let part: Daypart
    let averageStress: Double
    let sampleCount: Int

    /// Buckets below this are shown greyed rather than compared.
    static let minimumSamples = 60
}
