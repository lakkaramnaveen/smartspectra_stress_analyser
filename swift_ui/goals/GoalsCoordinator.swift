import Foundation
import SwiftUI

/// Wires the evaluator, streak calculator, catalog, and store together
/// and publishes goal state for SwiftUI.
///
/// `AppModel` composes this the way it composes `SessionRecorder` and
/// `StressPredictionCoordinator`: one property, a handful of call sites.
@MainActor
final class GoalsCoordinator: ObservableObject {

    @Published private(set) var state: GoalsState
    @Published private(set) var progress: [GoalProgress] = []

    /// Achievements unlocked during this app run, for celebration UI.
    /// Cleared once shown — a toast that reappears every launch stops
    /// being a reward and becomes noise.
    @Published var pendingCelebrations: [Achievement] = []

    private let store: GoalsStoring
    private let sessionStore: SessionStoring
    private let evaluator: GoalEvaluator
    private let streakCalculator: StreakCalculator

    init(
        store: GoalsStoring? = nil,
        sessionStore: SessionStoring? = nil,
        evaluator: GoalEvaluator = GoalEvaluator(),
        streakCalculator: StreakCalculator = StreakCalculator()
    ) {
        // Constructed in the body rather than as default arguments:
        // default-argument expressions evaluate in a non-isolated
        // context, which trips actor-isolation checking.
        self.store = store ?? FileGoalsStore()
        self.sessionStore = sessionStore ?? FileSessionStore()
        self.evaluator = evaluator
        self.streakCalculator = streakCalculator
        self.state = (store ?? FileGoalsStore()).load()
    }

    // MARK: - Refresh

    /// Recompute streak, records, unlocks, and progress from session
    /// history. Call on appear and after a session ends.
    func refresh(latestSession: SessionRecording? = nil) {
        let summaries = sessionStore.loadSummaries()
        let calendar = Calendar.current

        let qualifyingDays = Set(summaries.map { calendar.startOfDay(for: $0.startedAt) })

        var updated = state
        updated.streak = streakCalculator.streak(from: qualifyingDays)
        updated.records.longestDayStreak = max(updated.records.longestDayStreak, updated.streak.best)
        updated.records.totalSessions = summaries.count

        if let session = latestSession {
            applyRecords(from: session, to: &updated.records)
        }

        let newlyUnlocked = reconcileUnlocks(in: &updated)

        state = updated
        persist()

        recomputeProgress(
            latestSession: latestSession,
            activeDays: streakCalculator.activeDaysThisWeek(from: qualifyingDays)
        )

        if !newlyUnlocked.isEmpty {
            pendingCelebrations.append(contentsOf: newlyUnlocked)
        }
    }

    /// Called when the user finishes a guided breathing exercise.
    func recordBreathingCompleted() {
        state.records.totalBreathingCompleted += 1
        let newlyUnlocked = reconcileUnlocks(in: &state)
        persist()
        if !newlyUnlocked.isEmpty {
            pendingCelebrations.append(contentsOf: newlyUnlocked)
        }
    }

    // MARK: - Goal management

    func setGoal(_ goal: Goal, enabled: Bool) {
        guard let index = state.goals.firstIndex(where: { $0.id == goal.id }) else { return }
        state.goals[index].isEnabled = enabled
        persist()
        recomputeProgress(latestSession: nil, activeDays: currentActiveDays())
    }

    func dismissCelebration(_ achievement: Achievement) {
        pendingCelebrations.removeAll { $0.id == achievement.id }
    }

    // MARK: - Derived

    var unlockedAchievements: [Achievement] {
        state.unlocked.compactMap { AchievementCatalog.achievement(id: $0.achievementID) }
    }

    var lockedAchievements: [Achievement] {
        let unlockedIDs = Set(state.unlocked.map(\.achievementID))
        return AchievementCatalog.all.filter { !unlockedIDs.contains($0.id) }
    }

    // MARK: - Private

    private func applyRecords(from session: SessionRecording, to records: inout PersonalRecords) {
        let facts = evaluator.facts(for: session)

        records.longestCalmRunSeconds = max(
            records.longestCalmRunSeconds ?? 0,
            facts.longestCalmRunSeconds
        )

        if session.peakStress > 0 {
            records.lowestSessionPeakStress = min(
                records.lowestSessionPeakStress ?? session.peakStress,
                session.peakStress
            )
        }

        if let recovery = facts.fastestRecoverySeconds {
            records.fastestRecoverySeconds = min(
                records.fastestRecoverySeconds ?? recovery,
                recovery
            )
        }
    }

    /// Diffs earned-vs-stored and returns anything newly unlocked.
    @discardableResult
    private func reconcileUnlocks(in state: inout GoalsState) -> [Achievement] {
        let earned = AchievementCatalog.earnedIDs(
            streak: state.streak,
            records: state.records
        )
        let alreadyUnlocked = Set(state.unlocked.map(\.achievementID))
        let newIDs = earned.subtracting(alreadyUnlocked)

        guard !newIDs.isEmpty else { return [] }

        let now = Date()
        state.unlocked.append(contentsOf: newIDs.map {
            UnlockedAchievement(achievementID: $0, unlockedAt: now)
        })

        return newIDs.compactMap { AchievementCatalog.achievement(id: $0) }
    }

    private func recomputeProgress(latestSession: SessionRecording?, activeDays: Int) {
        let facts = latestSession.map { evaluator.facts(for: $0) }

        progress = state.goals
            .filter(\.isEnabled)
            .map { goal in
                evaluator.progress(
                    for: goal,
                    facts: facts,
                    activeDaysThisWeek: activeDays,
                    breathingThisWeek: state.records.totalBreathingCompleted
                )
            }
    }

    private func currentActiveDays() -> Int {
        let calendar = Calendar.current
        let days = Set(sessionStore.loadSummaries().map { calendar.startOfDay(for: $0.startedAt) })
        return streakCalculator.activeDaysThisWeek(from: days)
    }

    private func persist() {
        do {
            try store.save(state)
        } catch {
            // Losing goal progress is annoying, not fatal — never let it
            // break the session flow it's attached to.
            print("GoalsCoordinator: failed to persist — \(error.localizedDescription)")
        }
    }
}
