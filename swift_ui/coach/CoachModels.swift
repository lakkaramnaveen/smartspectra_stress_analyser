import Foundation
import SwiftUI

// MARK: - Intervention Kind

/// Identifies which practice a piece of effectiveness data belongs to.
///
/// Deliberately an id + display name pair, not a reference to the live
/// `BreathingTechnique` / `Meditation` value — those can be edited or
/// deleted by the user, and historical effectiveness records need to
/// survive that (a deleted custom technique shouldn't erase the record
/// of how well it worked).
enum InterventionKind: Codable, Equatable, Sendable, Hashable {
    case breathing(id: String, name: String)
    case meditation(id: String, name: String)
    /// Added when this app started tracking Balloon Hunt as a real
    /// intervention rather than only breathing and meditation — "the
    /// game distracts me best from stress" is a real, checkable claim
    /// once the game's sessions feed the same effectiveness pipeline
    /// everything else does.
    case game(difficulty: String)

    var name: String {
        switch self {
        case .breathing(_, let name): return name
        case .meditation(_, let name): return name
        case .game(let difficulty): return "Balloon Hunt (\(difficulty))"
        }
    }

    var icon: String {
        switch self {
        case .breathing: return "wind"
        case .meditation: return "moon"
        case .game: return "gamecontroller"
        }
    }

    /// Stable grouping key, independent of display name — a renamed
    /// custom technique keeps its history.
    var key: String {
        switch self {
        case .breathing(let id, _): return "breathing.\(id)"
        case .meditation(let id, _): return "meditation.\(id)"
        case .game(let difficulty): return "game.\(difficulty)"
        }
    }

    /// Which broad category this belongs to — the basis for
    /// "meditation has worked better than breathing for you"
    /// comparisons, which operate on the category as a whole rather
    /// than any single technique inside it.
    var category: InterventionCategory {
        switch self {
        case .breathing: return .breathing
        case .meditation: return .meditation
        case .game: return .game
        }
    }
}

// MARK: - Category

enum InterventionCategory: String, Sendable, CaseIterable, Hashable {
    case breathing, meditation, game

    var label: String {
        switch self {
        case .breathing: return "Breathing"
        case .meditation: return "Meditation"
        case .game: return "The game"
        }
    }
}

/// Aggregate statistics for one *category* — every breathing technique
/// pooled together, every meditation pooled together, and so on.
struct CategoryEffectiveness: Identifiable, Sendable {
    var id: InterventionCategory { category }
    let category: InterventionCategory
    let attempts: Int
    let averageDelta: Double
    let confidence: CoachConfidence
}

// MARK: - Effectiveness Record

/// One completed use of an intervention, with the stress reading just
/// before it started and just before it ended.
///
/// Both are short windowed averages, not single samples — one reading
/// on either side is too noisy to anchor a comparison on, the same
/// reasoning behind the windowing in `MeditationStressAnalyzer`.
struct EffectivenessRecord: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let kind: InterventionKind
    let startedAt: Date
    let duration: TimeInterval
    let stressBefore: Double
    let stressAfter: Double
    let sampleCount: Int

    init(
        id: UUID = UUID(),
        kind: InterventionKind,
        startedAt: Date,
        duration: TimeInterval,
        stressBefore: Double,
        stressAfter: Double,
        sampleCount: Int
    ) {
        self.id = id
        self.kind = kind
        self.startedAt = startedAt
        self.duration = duration
        self.stressBefore = stressBefore
        self.stressAfter = stressAfter
        self.sampleCount = sampleCount
    }

    /// Negative means stress fell during the session.
    var delta: Double { stressAfter - stressBefore }
}

// MARK: - Confidence

/// How much weight a ranking should carry, based on how many times an
/// intervention has actually been used. A technique tried twice and one
/// tried thirty times shouldn't be presented as equally certain — same
/// gating principle as `InsightConfidence`, tuned for the much smaller
/// sample sizes a single user accumulates for a single technique.
enum CoachConfidence: Int, Comparable, Sendable {
    case exploratory = 0
    case moderate = 1
    case strong = 2

    var label: String {
        switch self {
        case .exploratory: return "Early signal"
        case .moderate: return "Some evidence"
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

    static func < (lhs: CoachConfidence, rhs: CoachConfidence) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    static func forSampleCount(_ count: Int) -> CoachConfidence {
        switch count {
        case ..<3: return .exploratory
        case 3..<8: return .moderate
        default: return .strong
        }
    }
}

// MARK: - Technique Effectiveness

/// Aggregate statistics for one intervention, across every recorded use.
struct TechniqueEffectiveness: Identifiable, Sendable {
    var id: String { kind.key }
    let kind: InterventionKind
    let attempts: Int
    let averageDelta: Double
    let averageDuration: TimeInterval
    let confidence: CoachConfidence
}

// MARK: - Recommendation

/// A single suggestion surfaced on the Coach tab.
struct CoachRecommendation: Identifiable, Sendable {
    enum Kind: Sendable {
        case bestTechnique(TechniqueEffectiveness)
        case timeOfDay(hour: Int, averageStress: Double)
        /// "Meditation has tended to help more than breathing for you"
        /// — the comparison the original spec asked for, without the
        /// multiplier. See `CoachEngine.categoryComparison` for why a
        /// precise "2x better" ratio isn't reported: a ratio between two
        /// small, noisy sample averages is *less* stable than either
        /// average alone, so this shows both point-deltas side by side
        /// instead of collapsing them into one number.
        case categoryComparison(better: InterventionCategory, worse: InterventionCategory, betterPoints: Double, worsePoints: Double)
    }

    let id = UUID()
    let kind: Kind
    let headline: String
    let detail: String
    let confidence: CoachConfidence

    var icon: String {
        switch kind {
        case .bestTechnique: return "star.fill"
        case .timeOfDay: return "clock.fill"
        case .categoryComparison: return "arrow.left.arrow.right"
        }
    }
}
