import Foundation

/// The full set of achievements, plus the logic deciding which are
/// unlocked given current progress.
///
/// Stable string IDs (not `UUID`) so a user's unlocks survive edits to
/// this catalog — renaming a title or changing an icon must never
/// silently re-lock something someone already earned.
enum AchievementCatalog {

    // MARK: - Definitions

    static let all: [Achievement] = consistency + practice + milestones

    /// Consistency achievements reward showing up. These are the ones
    /// most within a user's control, so they carry the higher tiers.
    static let consistency: [Achievement] = [
        Achievement(
            id: "streak.3",
            title: "Three in a row",
            detail: "Recorded sessions three days running",
            icon: "flame",
            tier: .bronze
        ),
        Achievement(
            id: "streak.7",
            title: "Full week",
            detail: "Seven consecutive days",
            icon: "flame.fill",
            tier: .silver
        ),
        Achievement(
            id: "streak.30",
            title: "A month of showing up",
            detail: "Thirty consecutive days",
            icon: "crown.fill",
            tier: .gold
        )
    ]

    /// Practice achievements reward using the interventions, not
    /// achieving particular readings.
    static let practice: [Achievement] = [
        Achievement(
            id: "breathing.1",
            title: "First breath",
            detail: "Completed a guided breathing exercise",
            icon: "wind",
            tier: .bronze
        ),
        Achievement(
            id: "breathing.10",
            title: "Ten breaks taken",
            detail: "Completed ten breathing exercises",
            icon: "wind.circle.fill",
            tier: .silver
        ),
        Achievement(
            id: "breathing.50",
            title: "Fifty breathing breaks",
            detail: "Completed fifty guided exercises",
            icon: "lungs.fill",
            tier: .gold
        )
    ]

    /// Milestone achievements mark accumulated practice. Note there is
    /// deliberately no "lowest stress score" achievement — rewarding a
    /// low reading incentivises gaming the sensor (sitting perfectly
    /// still, holding your breath, avoiding the app on hard days), and
    /// none of those are wellness.
    static let milestones: [Achievement] = [
        Achievement(
            id: "sessions.1",
            title: "First session",
            detail: "Recorded your first session",
            icon: "record.circle",
            tier: .bronze
        ),
        Achievement(
            id: "sessions.25",
            title: "Twenty-five sessions",
            detail: "Built a real body of data",
            icon: "chart.bar.fill",
            tier: .silver
        ),
        Achievement(
            id: "calm.10min",
            title: "Ten calm minutes",
            detail: "Held below your calm threshold for ten minutes straight",
            icon: "leaf.fill",
            tier: .silver
        ),
        Achievement(
            id: "sessions.100",
            title: "One hundred sessions",
            detail: "A sustained practice",
            icon: "star.circle.fill",
            tier: .gold
        )
    ]

    static func achievement(id: String) -> Achievement? {
        all.first { $0.id == id }
    }

    // MARK: - Unlock evaluation

    /// Returns the IDs of every achievement earned by the given state.
    ///
    /// Pure and idempotent: it reports what *should* be unlocked, and the
    /// caller diffs against what already is. That means a corrupted or
    /// partially-written unlock list self-heals on the next evaluation,
    /// rather than leaving an achievement permanently unearnable.
    static func earnedIDs(streak: StreakState, records: PersonalRecords) -> Set<String> {
        var earned: Set<String> = []

        // Consistency — measured against best-ever, so a lapsed streak
        // never revokes something already achieved.
        if streak.best >= 3 { earned.insert("streak.3") }
        if streak.best >= 7 { earned.insert("streak.7") }
        if streak.best >= 30 { earned.insert("streak.30") }

        // Practice
        if records.totalBreathingCompleted >= 1 { earned.insert("breathing.1") }
        if records.totalBreathingCompleted >= 10 { earned.insert("breathing.10") }
        if records.totalBreathingCompleted >= 50 { earned.insert("breathing.50") }

        // Milestones
        if records.totalSessions >= 1 { earned.insert("sessions.1") }
        if records.totalSessions >= 25 { earned.insert("sessions.25") }
        if records.totalSessions >= 100 { earned.insert("sessions.100") }

        if let calmRun = records.longestCalmRunSeconds, calmRun >= 600 {
            earned.insert("calm.10min")
        }

        return earned
    }
}
