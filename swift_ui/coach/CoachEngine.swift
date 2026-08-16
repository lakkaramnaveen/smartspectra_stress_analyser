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
