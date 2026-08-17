import Foundation

/// Assembles a `TherapistReport` from data already on disk.
///
/// Reuses `SessionAggregator` (from Insights) and `SleepStressAnalyzer`
/// (from Sleep) rather than recomputing trend or association math a
/// second, slightly-different way — the same discipline `Coach` and
/// `FamilyDashboardCoordinator` followed. A report shown to a clinician
/// should say the same thing the app's own dashboards say, not a
/// second, independently-derived version of it.
///
/// No network calls anywhere in this file. A clinician-facing summary
/// shouldn't depend on a third-party service being reachable, and
/// there's no reason for it to be — everything here already lives
/// locally.
struct TherapistReportBuilder: Sendable {
    private let sessionAggregator = SessionAggregator()
    private let sleepAnalyzer = SleepStressAnalyzer()

    func build(
        config: TherapistReportConfig,
        profile: UserProfile,
        recordings: [SessionRecording],
        goalsState: GoalsState,
        sleepEntries: [SleepEntry],
        notes: [SessionNote]
    ) -> TherapistReport {
        let (start, end) = config.dateRange.bounds()

        // Scoping to the chosen window is itself a form of "least data
        // necessary" — not a compliance claim, just the same instinct:
        // a therapist asked for the last month doesn't need the
        // person's entire history.
        let scopedRecordings = recordings.filter { $0.startedAt >= start && $0.startedAt <= end }
        let scopedNotes = notes.filter { $0.date >= start && $0.date <= end }

        let aggregates = sessionAggregator.aggregate(scopedRecordings)
        let stressValues = scopedRecordings.map(\.averageStress)
        let average = stressValues.isEmpty ? nil : stressValues.average
        let peak = scopedRecordings.map(\.peakStress).max()

        let sleepAssociation = config.includedSections.contains(.sleep)
            ? sleepAnalyzer.associate(entries: sleepEntries, recordings: scopedRecordings)
            : nil

        return TherapistReport(
            config: config,
            generatedAt: Date(),
            profileName: config.includeIdentifyingHeader ? profile.name : nil,
            sessionCount: scopedRecordings.count,
            averageStress: average,
            peakStress: peak,
            weeklyTrend: aggregates.weeklyTrend,
            sleepAssociation: sleepAssociation,
            currentStreak: goalsState.streak.current,
            bestStreakEver: goalsState.records.longestDayStreak,
            breathingSessionsCompleted: goalsState.records.totalBreathingCompleted,
            notes: config.includedSections.contains(.notes) ? scopedNotes : []
        )
    }
}
