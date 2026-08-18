import Foundation

/// An observation about a *sustained* pattern in weekly averages —
/// deliberately not a "burnout score" and not a projected date.
///
/// A slope fit over a handful of noisy weekly averages can honestly say
/// "this has been trending up" or "this has stayed elevated." It cannot
/// honestly say "6 weeks until burnout" — that's a specific, consequential
/// claim about a serious outcome, built on camera-derived data with all
/// the accuracy caveats this app has been honest about everywhere else
/// (lighting, motion, no clinical validation). Being wrong in either
/// direction here has real cost: false alarm causes needless distress,
/// false reassurance could discourage someone who's actually struggling
/// from taking it seriously. Burnout is too consequential a topic to
/// make an exception for the restraint this app applies everywhere else.
struct SustainedPatternObservation: Sendable, Equatable {
    let headline: String
    let detail: String
    let weeksObserved: Int

    /// Gates whether `InsightsDashboardView` shows resources and a
    /// pointer to Provider Report. Reserved for a genuinely sustained
    /// run of elevated weeks — not triggered by an ordinarily busy
    /// fortnight.
    let warrantsSupportPointer: Bool
}

struct LongTermTrendAnalyzer: Sendable {

    let minimumWeeks: Int
    let sustainedWeeksForSupportPointer: Int

    init(minimumWeeks: Int = 6, sustainedWeeksForSupportPointer: Int = 6) {
        self.minimumWeeks = minimumWeeks
        self.sustainedWeeksForSupportPointer = sustainedWeeksForSupportPointer
    }

    func observe(from weeklyTrend: [WeeklyTrendPoint]) -> SustainedPatternObservation? {
        let sorted = weeklyTrend.sorted { $0.weekStart < $1.weekStart }
        guard sorted.count >= minimumWeeks else { return nil }

        // Look back up to roughly three months — old weeks shouldn't
        // keep pulling on a "sustained" read of the present.
        let recent = Array(sorted.suffix(12))

        let isElevatedOrAbove: (WeeklyTrendPoint) -> Bool = {
            let level = StressLevel.classify($0.averageStress)
            return level == .elevated || level == .critical
        }

        // Consecutive elevated-or-above weeks counting back from today
        // — a real, sustained run, not just a count of bad weeks
        // scattered across the period.
        let consecutiveFromEnd = recent.reversed().prefix(while: isElevatedOrAbove).count

        guard let fit = LinearFit(xs: recent.indices.map(Double.init), ys: recent.map(\.averageStress)) else {
            return nil
        }

        // Both thresholds are deliberately conservative: a slope this
        // shallow or a fit this loose is easily noise across a handful
        // of weekly averages, and saying nothing is the safer default
        // than a shaky claim about something this consequential.
        let isRising = fit.slope > 0.005 && fit.rSquared > 0.25
        let isSustainedElevated = consecutiveFromEnd >= 3

        guard isRising || isSustainedElevated else { return nil }

        let headline: String
        if isSustainedElevated && isRising {
            headline = "Your average stress has been elevated and still climbing over the past \(consecutiveFromEnd) weeks"
        } else if isSustainedElevated {
            headline = "Your average stress has stayed elevated for \(consecutiveFromEnd) weeks running"
        } else {
            headline = "Your average stress has been trending upward over the past \(recent.count) weeks"
        }

        return SustainedPatternObservation(
            headline: headline,
            detail: "This describes a pattern in your own readings — it isn't a diagnosis and it can't predict what happens next. If it matches how you've actually been feeling, it may be worth paying attention to.",
            weeksObserved: recent.count,
            warrantsSupportPointer: consecutiveFromEnd >= sustainedWeeksForSupportPointer
        )
    }
}
