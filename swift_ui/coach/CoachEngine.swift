import Foundation

/// Turns a history of `EffectivenessRecord`s into ranked, evidence-gated
/// recommendations.
///
/// This is arithmetic over the user's own logged sessions — means and
/// sample counts — not a trained model. There's no CoreML here and
/// nothing inferred beyond what a mean and a confidence interval-sized
/// sample count actually support. See the permanent note on
/// `CoachTabView` for why that distinction is stated to the user
/// directly rather than left implicit behind the name "Coach".
struct CoachEngine: Sendable {

    /// Minimum uses before a technique is ranked at all. Two rather than
    /// one: a single use has no way to distinguish "this technique
    /// works" from "stress happened to be falling anyway that day."
    let minimumAttempts: Int

    init(minimumAttempts: Int = 2) {
        self.minimumAttempts = minimumAttempts
    }

    // MARK: - Technique ranking

    func effectiveness(from records: [EffectivenessRecord]) -> [TechniqueEffectiveness] {
        let grouped = Dictionary(grouping: records) { $0.kind.key }

        return grouped.compactMap { _, records -> TechniqueEffectiveness? in
            guard records.count >= minimumAttempts, let kind = records.first?.kind else {
                return nil
            }

            return TechniqueEffectiveness(
                kind: kind,
                attempts: records.count,
                averageDelta: records.map(\.delta).average,
                averageDuration: records.map(\.duration).average,
                confidence: .forSampleCount(records.count)
            )
        }
        // Most negative delta (biggest stress drop) first.
        .sorted { $0.averageDelta < $1.averageDelta }
    }

    // MARK: - Category ranking

    /// Every technique in a category pooled together — "meditation as a
    /// whole" rather than any one specific meditation. This is what a
    /// category-vs-category comparison needs: an individual technique
    /// might have too few uses to rank on its own while the category it
    /// belongs to has plenty.
    func categoryEffectiveness(from records: [EffectivenessRecord]) -> [CategoryEffectiveness] {
        let grouped = Dictionary(grouping: records) { $0.kind.category }

        return grouped.compactMap { category, records -> CategoryEffectiveness? in
            guard records.count >= minimumAttempts else { return nil }
            return CategoryEffectiveness(
                category: category,
                attempts: records.count,
                averageDelta: records.map(\.delta).average,
                confidence: .forSampleCount(records.count)
            )
        }
        .sorted { $0.averageDelta < $1.averageDelta }
    }

    /// A comparison like "meditation has tended to help more than
    /// breathing for you" — the specific claim the original spec asked
    /// for ("meditation works 2x better than breathing"), deliberately
    /// without the multiplier.
    ///
    /// A ratio of two averages is the easiest number in this file to
    /// state with more confidence than it deserves: two small, noisy
    /// sample means can produce a dramatic-looking ratio purely from
    /// noise, and a ratio near 1 isn't worth reporting as a comparison
    /// at all. Reporting "1.3x" still implies a precision neither
    /// average actually has. An ordinal comparison — which one helped
    /// more, by how many points each — survives that noise in a way a
    /// multiplier doesn't, so that's what this reports instead. Every
    /// gate below exists to keep even that more modest claim honest:
    ///
    ///   - both categories must individually clear the confidence bar
    ///     (not just the pair together)
    ///   - both must show a genuine net-calming effect — comparing the
    ///     "less bad of two unhelpful options" would be misleading
    ///     framed as one being "better"
    ///   - the point gap between them must be large enough to be a real
    ///     difference, not noise dressed as one
    func categoryComparison(from categories: [CategoryEffectiveness]) -> CoachRecommendation? {
        let eligible = categories.filter { $0.confidence >= .moderate && $0.averageDelta < -0.02 }
        guard eligible.count >= 2 else { return nil }

        let sorted = eligible.sorted { $0.averageDelta < $1.averageDelta }
        guard let best = sorted.first, let second = sorted.dropFirst().first else { return nil }

        // Points, not a ratio — see the note above. A gap under ~4
        // points is well within the noise two small samples can produce
        // and isn't worth reporting as a difference at all.
        let gapPoints = (second.averageDelta - best.averageDelta) * 100
        guard gapPoints >= 4 else { return nil }

        return CoachRecommendation(
            kind: .categoryComparison(
                better: best.category,
                worse: second.category,
                betterPoints: -best.averageDelta * 100,
                worsePoints: -second.averageDelta * 100
            ),
            headline: "\(best.category.label) has tended to help more than \(second.category.label.lowercased()) for you",
            detail: String(
                format: "%@ averaged about %.0f points off; %@ averaged about %.0f points off, across %d and %d uses.",
                best.category.label, -best.averageDelta * 100,
                second.category.label, -second.averageDelta * 100,
                best.attempts, second.attempts
            ),
            confidence: min(best.confidence, second.confidence)
        )
    }

    /// Ranks by how quickly a technique's sessions tended to run,
    /// restricted to techniques that measurably helped at all — ranking
    /// something by how fast it doesn't work isn't a useful comparison,
    /// so a technique needs a real stress drop before speed is worth
    /// ranking it on. Reuses `effectiveness(from:)` rather than
    /// re-deriving the join and evidence gates a second way.
    func fastestRecovery(from records: [EffectivenessRecord]) -> [TechniqueEffectiveness] {
        effectiveness(from: records)
            .filter { $0.averageDelta < -0.03 }
            .sorted { $0.averageDuration < $1.averageDuration }
    }

    // MARK: - Recommendations

    /// Builds the recommendation list shown on the Coach tab.
    ///
    /// - Parameter hourBuckets: passed in from `SessionAggregator` rather
    ///   than recomputed here. Insights already owns time-of-day
    ///   aggregation; duplicating that logic in a second file would be
    ///   one more place for the two features to quietly drift apart from
    ///   each other on the same underlying data.
    func recommendations(
        from records: [EffectivenessRecord],
        hourBuckets: [HourBucket]
    ) -> [CoachRecommendation] {
        var results: [CoachRecommendation] = []

        let ranked = effectiveness(from: records)
        if let best = ranked.first, best.averageDelta < -0.03 {
            let points = Int((-best.averageDelta * 100).rounded())
            results.append(
                CoachRecommendation(
                    kind: .bestTechnique(best),
                    headline: "\(best.kind.name) has worked best for you",
                    detail: "Across \(best.attempts) uses, your stress reading dropped by about \(points) points on average, typically over \(Int(best.averageDuration))s.",
                    confidence: best.confidence
                )
            )
        }

        if let comparison = categoryComparison(from: categoryEffectiveness(from: records)) {
            results.append(comparison)
        }

        // Same thresholds Insights uses for its own time-of-day insight
        // — a bucket needs real spread across days, not just a busy
        // afternoon once.
        let eligible = hourBuckets.filter { $0.sampleCount >= 30 && $0.distinctDays >= 4 }
        if let peak = eligible.max(by: { $0.averageStress < $1.averageStress }) {
            results.append(
                CoachRecommendation(
                    kind: .timeOfDay(hour: peak.hour, averageStress: peak.averageStress),
                    headline: "Readings tend to run higher around \(clockLabel(peak.hour))",
                    detail: "Worth having a technique ready before that window, rather than reaching for one once stress has already climbed.",
                    confidence: peak.distinctDays >= 10 ? .strong : .moderate
                )
            )
        }

        return results
    }

    private func clockLabel(_ hour: Int) -> String {
        switch hour {
        case 0: return "12 AM"
        case 12: return "12 PM"
        case 1..<12: return "\(hour) AM"
        default: return "\(hour - 12) PM"
        }
    }
}
