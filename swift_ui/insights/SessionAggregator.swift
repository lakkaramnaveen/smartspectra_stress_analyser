import Foundation

/// Reduces raw session recordings into the aggregate statistics the
/// insight generator reads.
///
/// Pure and `Sendable`-safe: takes value types in, returns value types
/// out, touches no storage and no UI. That means it can run on a
/// background task without any actor gymnastics, which matters because
/// this is the expensive part — a few hundred sessions is tens of
/// thousands of snapshots.
struct SessionAggregator: Sendable {

    /// Sampling cadence of `SessionRecorder`, needed to convert lag in
    /// samples into lag in seconds. Injected rather than hardcoded so the
    /// two stay in sync if the recorder's interval changes.
    let samplingInterval: TimeInterval

    /// Widest lead the lead-lag scan will consider, in seconds.
    let maxLeadSeconds: TimeInterval

    init(samplingInterval: TimeInterval = 1.0, maxLeadSeconds: TimeInterval = 60) {
        self.samplingInterval = samplingInterval
        self.maxLeadSeconds = maxLeadSeconds
    }

    func aggregate(_ recordings: [SessionRecording]) -> InsightAggregates {
        guard !recordings.isEmpty else { return .empty }

        let calendar = Calendar.current
        let allSnapshots = recordings.flatMap(\.snapshots)

        guard !allSnapshots.isEmpty else { return .empty }

        return InsightAggregates(
            hourBuckets: buildHourBuckets(from: allSnapshots, calendar: calendar),
            weekdayBuckets: buildWeekdayBuckets(from: recordings, calendar: calendar),
            weeklyTrend: buildWeeklyTrend(from: recordings, calendar: calendar),
            totalSessions: recordings.count,
            totalSnapshots: allSnapshots.count,
            distinctDays: distinctDayCount(recordings, calendar: calendar),
            heartRateCorrelation: CorrelationAnalyzer.pearson(
                allSnapshots.map(\.heartRate),
                allSnapshots.map(\.stressScore)
            ),
            breathingCorrelation: CorrelationAnalyzer.pearson(
                allSnapshots.map(\.breathingRate),
                allSnapshots.map(\.stressScore)
            ),
            edaCorrelation: CorrelationAnalyzer.pearson(
                allSnapshots.map(\.eda),
                allSnapshots.map(\.stressScore)
            ),
            edaLeadSeconds: edaLead(in: recordings)?.seconds,
            edaLeadStrength: edaLead(in: recordings)?.strength
        )
    }

    // MARK: - Time of day

    private func buildHourBuckets(
        from snapshots: [SessionSnapshot],
        calendar: Calendar
    ) -> [HourBucket] {
        var scoresByHour: [Int: [Double]] = [:]
        var daysByHour: [Int: Set<Date>] = [:]

        for snapshot in snapshots {
            let hour = calendar.component(.hour, from: snapshot.timestamp)
            scoresByHour[hour, default: []].append(snapshot.stressScore)
            daysByHour[hour, default: []].insert(calendar.startOfDay(for: snapshot.timestamp))
        }

        return scoresByHour
            .map { hour, scores in
                HourBucket(
                    hour: hour,
                    averageStress: scores.average,
                    sampleCount: scores.count,
                    distinctDays: daysByHour[hour]?.count ?? 0
                )
            }
            .sorted { $0.hour < $1.hour }
    }

    // MARK: - Day of week

    private func buildWeekdayBuckets(
        from recordings: [SessionRecording],
        calendar: Calendar
    ) -> [WeekdayBucket] {
        var scoresByWeekday: [Int: [Double]] = [:]

        for recording in recordings where !recording.snapshots.isEmpty {
            let weekday = calendar.component(.weekday, from: recording.startedAt)
            scoresByWeekday[weekday, default: []].append(recording.averageStress)
        }

        return scoresByWeekday
            .map { weekday, sessionAverages in
                WeekdayBucket(
                    weekday: weekday,
                    averageStress: sessionAverages.average,
                    sessionCount: sessionAverages.count
                )
            }
            .sorted { $0.weekday < $1.weekday }
    }

    // MARK: - Weekly trend

    private func buildWeeklyTrend(
        from recordings: [SessionRecording],
        calendar: Calendar
    ) -> [WeeklyTrendPoint] {
        var byWeek: [Date: [SessionRecording]] = [:]

        for recording in recordings where !recording.snapshots.isEmpty {
            guard let weekStart = calendar.dateInterval(
                of: .weekOfYear,
                for: recording.startedAt
            )?.start else { continue }
            byWeek[weekStart, default: []].append(recording)
        }

        return byWeek
            .map { weekStart, weekRecordings in
                WeeklyTrendPoint(
                    weekStart: weekStart,
                    averageStress: weekRecordings.map(\.averageStress).average,
                    peakStress: weekRecordings.map(\.peakStress).max() ?? 0,
                    sessionCount: weekRecordings.count
                )
            }
            .sorted { $0.weekStart < $1.weekStart }
    }

    // MARK: - EDA lead

    /// Computes the lead-lag relationship per session, then averages.
    ///
    /// Per-session rather than across the concatenated history on
    /// purpose: splicing separate sessions end-to-end would create
    /// artificial jumps at every boundary, and the scan would happily
    /// correlate across those seams as though they were continuous time.
    private func edaLead(in recordings: [SessionRecording]) -> (seconds: Double, strength: Double)? {
        let maxLagSamples = Int(maxLeadSeconds / samplingInterval)
        guard maxLagSamples > 0 else { return nil }

        var lags: [Double] = []
        var strengths: [Double] = []

        for recording in recordings {
            let sorted = recording.snapshots.sorted { $0.timestamp < $1.timestamp }
            guard sorted.count > maxLagSamples + 3 else { continue }

            guard let result = CorrelationAnalyzer.bestLead(
                leading: sorted.map(\.eda),
                following: sorted.map(\.stressScore),
                maxLagSamples: maxLagSamples
            ) else { continue }

            lags.append(Double(result.lagSamples) * samplingInterval)
            strengths.append(result.correlation)
        }

        guard !lags.isEmpty else { return nil }
        return (lags.average, strengths.average)
    }

    // MARK: - Misc

    private func distinctDayCount(_ recordings: [SessionRecording], calendar: Calendar) -> Int {
        Set(recordings.map { calendar.startOfDay(for: $0.startedAt) }).count
    }
}
