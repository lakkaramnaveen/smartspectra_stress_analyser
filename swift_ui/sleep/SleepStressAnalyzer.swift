import Foundation

/// Joins logged nights against session data and looks for an association.
///
/// Pure and UI-free — same shape as `CorrelationAnalyzer` and
/// `StressScoringEngine`. Reuses `CorrelationAnalyzer.pearson` rather
/// than reimplementing it.
struct SleepStressAnalyzer: Sendable {

    /// Weighting between hours slept and subjective rest quality when
    /// forming a single "rest score" per night.
    ///
    /// Quality is weighted slightly higher than duration on purpose:
    /// self-reported hours are a rough estimate ("about seven?") while
    /// how rested someone feels is a direct report of the thing that
    /// matters for the day ahead.
    let hoursWeight: Double
    let qualityWeight: Double

    init(hoursWeight: Double = 0.45, qualityWeight: Double = 0.55) {
        self.hoursWeight = hoursWeight
        self.qualityWeight = qualityWeight
    }

    // MARK: - Rest score

    /// Combines hours and quality into 0...1.
    ///
    /// Hours are normalised against a 5–9 hour window rather than
    /// linearly across the full slider: the difference between five and
    /// seven hours matters far more than between nine and eleven, and a
    /// linear scale would treat a very long night as strictly better,
    /// which isn't how rest works.
    func restScore(for entry: SleepEntry) -> Double {
        let normalisedHours = ((entry.hours - 5.0) / 4.0).clamped(to: 0...1)
        let normalisedQuality = Double(entry.quality.rawValue) / 3.0
        return (normalisedHours * hoursWeight) + (normalisedQuality * qualityWeight)
    }

    // MARK: - Association

    /// Correlate rest against the mean stress of each following day.
    func associate(
        entries: [SleepEntry],
        recordings: [SessionRecording],
        calendar: Calendar = .current
    ) -> SleepAssociation {

        // Mean stress per calendar day, across all sessions that day.
        var stressByDay: [Date: [Double]] = [:]
        for recording in recordings {
            let day = calendar.startOfDay(for: recording.startedAt)
            guard !recording.snapshots.isEmpty else { continue }
            stressByDay[day, default: []].append(recording.averageStress)
        }

        // Pair each logged night with the day it precedes. Nights with no
        // session that day contribute nothing — there's no reading to
        // compare against, and imputing one would be inventing data.
        var restScores: [Double] = []
        var dailyStress: [Double] = []

        for entry in entries {
            guard let dayScores = stressByDay[entry.forDay], !dayScores.isEmpty else { continue }
            restScores.append(restScore(for: entry))
            dailyStress.append(dayScores.average)
        }

        guard restScores.count >= SleepAssociation.minimumNights else {
            return SleepAssociation(
                direction: .insufficientData,
                nightsCompared: restScores.count,
                coefficient: nil,
                stressAfterBestRest: nil,
                stressAfterLeastRest: nil
            )
        }

        guard let r = CorrelationAnalyzer.pearson(restScores, dailyStress) else {
            return SleepAssociation(
                direction: .noClearPattern,
                nightsCompared: restScores.count,
                coefficient: nil,
                stressAfterBestRest: nil,
                stressAfterLeastRest: nil
            )
        }

        // Tercile comparison alongside the coefficient. A correlation is
        // hard to read; "average stress after your most vs least restful
        // nights" is the same relationship in units a person can picture.
        let paired = zip(restScores, dailyStress)
            .sorted { $0.0 < $1.0 }
        let tercile = max(paired.count / 3, 1)

        let leastRested = paired.prefix(tercile).map(\.1).average
        let mostRested = paired.suffix(tercile).map(\.1).average

        guard abs(r) >= SleepAssociation.minimumCoefficient else {
            return SleepAssociation(
                direction: .noClearPattern,
                nightsCompared: restScores.count,
                coefficient: r,
                stressAfterBestRest: mostRested,
                stressAfterLeastRest: leastRested
            )
        }

        // Negative r means more rest ↔ lower stress.
        let direction: SleepAssociation.Direction =
            r < 0 ? .restRelatesToLowerStress : .restRelatesToHigherStress

        return SleepAssociation(
            direction: direction,
            nightsCompared: restScores.count,
            coefficient: r,
            stressAfterBestRest: mostRested,
            stressAfterLeastRest: leastRested
        )
    }

    // MARK: - Dayparts

    /// Mean stress by part of day, across all recordings.
    func dayparts(
        from recordings: [SessionRecording],
        calendar: Calendar = .current
    ) -> [DaypartStress] {
        var scoresByPart: [DaypartStress.Daypart: [Double]] = [:]

        for snapshot in recordings.flatMap(\.snapshots) {
            let hour = calendar.component(.hour, from: snapshot.timestamp)
            guard let part = DaypartStress.Daypart.allCases.first(where: {
                $0.hourRange.contains(hour)
            }) else { continue }
            scoresByPart[part, default: []].append(snapshot.stressScore)
        }

        return DaypartStress.Daypart.allCases.map { part in
            let scores = scoresByPart[part] ?? []
            return DaypartStress(
                part: part,
                averageStress: scores.average,
                sampleCount: scores.count
            )
        }
    }
}

// MARK: - Helpers

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
