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

    var name: String {
        switch self {
        case .breathing(_, let name): return name
        case .meditation(_, let name): return name
        }
    }

    var icon: String {
        switch self {
        case .breathing: return "wind"
        case .meditation: return "moon"
        }
    }

    /// Stable grouping key, independent of display name — a renamed
    /// custom technique keeps its history.
    var key: String {
        switch self {
        case .breathing(let id, _): return "breathing.\(id)"
        case .meditation(let id, _): return "meditation.\(id)"
        }
    }
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
        }
    }
}
