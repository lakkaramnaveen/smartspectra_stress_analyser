import Foundation

// MARK: - Configuration

/// Evidence thresholds. Every one of these exists to stop the generator
/// producing a confident sentence from too little data — the single
/// biggest failure mode for a feature like this.
struct InsightThresholds {
    /// No insights at all below this many completed sessions.
    var minimumSessions: Int = 5

    /// Time-of-day claims need this many separate calendar days, not
    /// just this many sessions. Six sessions on one afternoon tell you
    /// about that afternoon, not about afternoons.
    var minimumDistinctDaysForTimeOfDay: Int = 4

    /// An hour bucket must have at least this many samples to be named
    /// as a peak or trough.
    var minimumSamplesPerHourBucket: Int = 30

    /// Two hour-buckets must differ by at least this much stress before
    /// the difference is worth reporting.
    var minimumStressGapToReport: Double = 0.10

    /// Weekday comparisons need this many sessions on each side.
    var minimumSessionsPerWeekdayGroup: Int = 3

    /// |r| below this is treated as no relationship worth mentioning.
    var minimumCorrelationToReport: Double = 0.35

    /// Lead-lag results below this strength, or under this many seconds,
    /// aren't reported — a two-second "lead" is indistinguishable from
    /// sampling jitter.
    var minimumLeadStrength: Double = 0.4
    var minimumLeadSeconds: Double = 5

    /// Weeks needed before week-over-week change is reported.
    var minimumWeeksForTrend: Int = 2

    static let `default` = InsightThresholds()
}

// MARK: - Generator

/// Turns aggregate statistics into readable observations.
///
/// This is template-driven prose over descriptive statistics — not a
/// model, and not "AI" in any meaningful sense. Naming it accurately
/// matters here: a user who believes an algorithm has diagnosed their
/// afternoons will act on it more readily than one who understands they
/// are reading an average over a handful of sessions.
///
/// Every generator method returns `nil` unless its evidence threshold is
/// met, so a thin history produces *fewer* insights rather than weaker
/// ones stated just as confidently.
struct InsightGenerator {
    let thresholds: InsightThresholds

    init(thresholds: InsightThresholds = .default) {
        self.thresholds = thresholds
    }

    func generate(from aggregates: InsightAggregates) -> [Insight] {
        guard aggregates.totalSessions >= thresholds.minimumSessions else { return [] }

        return [
            peakHourInsight(aggregates),
            calmestHourInsight(aggregates),
            weekendInsight(aggregates),
            correlationInsight(aggregates),
            edaLeadInsight(aggregates),
            weeklyTrendInsight(aggregates)
        ]
        .compactMap { $0 }
        .sorted { $0.confidence > $1.confidence }
    }

    // MARK: - Time of day

    private func peakHourInsight(_ aggregates: InsightAggregates) -> Insight? {
        guard aggregates.distinctDays >= thresholds.minimumDistinctDaysForTimeOfDay else { return nil }

        let eligible = aggregates.hourBuckets.filter {
            $0.sampleCount >= thresholds.minimumSamplesPerHourBucket
        }
        guard eligible.count >= 3,
              let peak = eligible.max(by: { $0.averageStress < $1.averageStress }),
              let trough = eligible.min(by: { $0.averageStress < $1.averageStress }),
              peak.averageStress - trough.averageStress >= thresholds.minimumStressGapToReport else {
            return nil
        }

        let confidence = confidenceFor(
            distinctDays: peak.distinctDays,
            effectSize: peak.averageStress - trough.averageStress
        )

        return Insight(
            category: .timeOfDay,
            confidence: confidence,
            headline: "Stress tends to run highest around \(formatHourRange(peak.hour))",
            detail: "Across \(peak.distinctDays) days, your average stress in that window was \(percent(peak.averageStress)) — about \(percent(peak.averageStress - trough.averageStress)) higher than your calmest hour.",
            sessionCount: aggregates.totalSessions,
            suggestion: "If that window is flexible, it may be worth protecting it from your most demanding work."
        )
    }

    private func calmestHourInsight(_ aggregates: InsightAggregates) -> Insight? {
        guard aggregates.distinctDays >= thresholds.minimumDistinctDaysForTimeOfDay else { return nil }

        let eligible = aggregates.hourBuckets.filter {
            $0.sampleCount >= thresholds.minimumSamplesPerHourBucket
        }
        guard eligible.count >= 3,
              let calmest = eligible.min(by: { $0.averageStress < $1.averageStress }) else {
            return nil
        }

        return Insight(
            category: .timeOfDay,
            confidence: confidenceFor(distinctDays: calmest.distinctDays, effectSize: 0.15),
            headline: "\(formatHourRange(calmest.hour).capitalized) has been your steadiest window",
            detail: "Average stress of \(percent(calmest.averageStress)) across \(calmest.distinctDays) days of data.",
            sessionCount: aggregates.totalSessions,
            suggestion: "A reasonable slot for work that needs sustained focus."
        )
    }

    // MARK: - Day of week

    private func weekendInsight(_ aggregates: InsightAggregates) -> Insight? {
        // Calendar weekday: 1 = Sunday, 7 = Saturday.
        let weekend = aggregates.weekdayBuckets.filter { $0.weekday == 1 || $0.weekday == 7 }
        let weekday = aggregates.weekdayBuckets.filter { $0.weekday > 1 && $0.weekday < 7 }

        let weekendSessions = weekend.reduce(0) { $0 + $1.sessionCount }
        let weekdaySessions = weekday.reduce(0) { $0 + $1.sessionCount }

        guard weekendSessions >= thresholds.minimumSessionsPerWeekdayGroup,
              weekdaySessions >= thresholds.minimumSessionsPerWeekdayGroup else {
            return nil
        }

        let weekendAvg = weekend.map(\.averageStress).average
        let weekdayAvg = weekday.map(\.averageStress).average
        let gap = weekdayAvg - weekendAvg

        guard abs(gap) >= thresholds.minimumStressGapToReport else { return nil }

        let calmerSide = gap > 0 ? "Weekends" : "Weekdays"
        let busierSide = gap > 0 ? "weekdays" : "weekends"

        return Insight(
            category: .dayOfWeek,
            confidence: weekendSessions + weekdaySessions >= 20 ? .moderate : .exploratory,
            headline: "\(calmerSide) have been calmer than \(busierSide)",
            detail: "Average stress of \(percent(min(weekendAvg, weekdayAvg))) versus \(percent(max(weekendAvg, weekdayAvg))), across \(weekendSessions + weekdaySessions) sessions.",
            sessionCount: weekendSessions + weekdaySessions,
            suggestion: nil
        )
    }

    // MARK: - Correlation

    private func correlationInsight(_ aggregates: InsightAggregates) -> Insight? {
        let candidates: [(name: String, r: Double?)] = [
            ("breathing rate", aggregates.breathingCorrelation),
            ("heart rate", aggregates.heartRateCorrelation),
            ("skin conductance", aggregates.edaCorrelation)
        ]

        let strongest = candidates
            .compactMap { candidate -> (String, Double)? in
                guard let r = candidate.r else { return nil }
                return (candidate.name, r)
            }
            .max { abs($0.1) < abs($1.1) }

        guard let (name, r) = strongest,
              abs(r) >= thresholds.minimumCorrelationToReport else {
            return nil
        }

        let direction = r > 0 ? "rises alongside" : "falls as"
        let strength = CorrelationAnalyzer.strengthLabel(for: r)

        return Insight(
            category: .correlation,
            confidence: abs(r) >= 0.6 ? .strong : .moderate,
            headline: "Your \(name) tracks with your stress",
            detail: "There's \(strength) relationship (r = \(String(format: "%.2f", r))) — your \(name) \(direction) your stress score across \(aggregates.totalSnapshots) samples.",
            sessionCount: aggregates.totalSessions,
            suggestion: r > 0 ? "It may be a useful thing to notice in yourself before the stress score catches up." : nil
        )
    }

    // MARK: - Lead indicator

    private func edaLeadInsight(_ aggregates: InsightAggregates) -> Insight? {
        guard let seconds = aggregates.edaLeadSeconds,
              let strength = aggregates.edaLeadStrength,
              strength >= thresholds.minimumLeadStrength,
              seconds >= thresholds.minimumLeadSeconds else {
            return nil
        }

        return Insight(
            category: .leadIndicator,
            confidence: strength >= 0.6 ? .moderate : .exploratory,
            headline: "Skin conductance tends to move about \(Int(seconds.rounded())) seconds before your stress score",
            detail: "In your sessions, changes in skin conductance line up most closely with stress readings roughly \(Int(seconds.rounded())) seconds later (r = \(String(format: "%.2f", strength))). Two signals moving in a consistent order doesn't mean one causes the other, but it may be a useful early cue.",
            sessionCount: aggregates.totalSessions,
            suggestion: nil
        )
    }

    // MARK: - Weekly trend

    private func weeklyTrendInsight(_ aggregates: InsightAggregates) -> Insight? {
        let weeks = aggregates.weeklyTrend
        guard weeks.count >= thresholds.minimumWeeksForTrend,
              let latest = weeks.last,
              let previous = weeks.dropLast().last else {
            return nil
        }

        let change = latest.averageStress - previous.averageStress
        guard abs(change) >= 0.05 else {
            return Insight(
                category: .trend,
                confidence: .moderate,
                headline: "Your weekly average has held steady",
                detail: "Average stress of \(percent(latest.averageStress)) this week, essentially unchanged from \(percent(previous.averageStress)) the week before.",
                sessionCount: latest.sessionCount + previous.sessionCount,
                suggestion: nil
            )
        }

        let improved = change < 0

        return Insight(
            category: .trend,
            confidence: latest.sessionCount >= 5 ? .moderate : .exploratory,
            headline: improved
                ? "Your average stress came down this week"
                : "Your average stress edged up this week",
            detail: "\(percent(latest.averageStress)) this week versus \(percent(previous.averageStress)) last week, across \(latest.sessionCount) sessions.",
            sessionCount: latest.sessionCount + previous.sessionCount,
            suggestion: improved ? nil : "One week is a short window — worth watching rather than reacting to."
        )
    }

    // MARK: - Helpers

    private func confidenceFor(distinctDays: Int, effectSize: Double) -> InsightConfidence {
        switch (distinctDays, effectSize) {
        case (14..., 0.15...): return .strong
        case (7..., 0.10...): return .moderate
        default: return .exploratory
        }
    }

    private func percent(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }

    private func formatHourRange(_ hour: Int) -> String {
        let end = (hour + 2) % 24
        return "\(clockLabel(hour))–\(clockLabel(end))"
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
