import XCTest
@testable import smartspectra_swift_ui

final class GoalEvaluatorTests: XCTestCase {

    private let evaluator = GoalEvaluator()
    private let base = Date(timeIntervalSince1970: 0)

    private func snapshot(offsetSeconds: TimeInterval, stressScore: Double) -> SessionSnapshot {
        SessionSnapshot(
            timestamp: base.addingTimeInterval(offsetSeconds),
            stressScore: stressScore,
            heartRate: 70,
            breathingRate: 14,
            eda: 0.02,
            emotionalState: "calm",
            gazeConfidence: 1
        )
    }

    // MARK: - longestCalmRun

    func test_longestCalmRun_returnsZeroForFewerThanTwoSnapshots() {
        XCTAssertEqual(evaluator.longestCalmRun(in: []), 0)
        XCTAssertEqual(evaluator.longestCalmRun(in: [snapshot(offsetSeconds: 0, stressScore: 0.1)]), 0)
    }

    func test_longestCalmRun_picksTheLongerOfTwoCalmStretches() {
        let snapshots = [
            snapshot(offsetSeconds: 0, stressScore: 0.1),   // calm run #1 starts
            snapshot(offsetSeconds: 10, stressScore: 0.2),  // still calm
            snapshot(offsetSeconds: 20, stressScore: 0.6),  // breaks run #1 (20s long)
            snapshot(offsetSeconds: 30, stressScore: 0.1),  // calm run #2 starts
            snapshot(offsetSeconds: 40, stressScore: 0.1),
            snapshot(offsetSeconds: 50, stressScore: 0.1),
            snapshot(offsetSeconds: 60, stressScore: 0.1)   // session ends calm (30s long)
        ]
        XCTAssertEqual(evaluator.longestCalmRun(in: snapshots), 30)
    }

    func test_longestCalmRun_zeroWhenNeverCalm() {
        let snapshots = [
            snapshot(offsetSeconds: 0, stressScore: 0.8),
            snapshot(offsetSeconds: 10, stressScore: 0.9)
        ]
        XCTAssertEqual(evaluator.longestCalmRun(in: snapshots), 0)
    }

    // MARK: - fastestRecovery

    func test_fastestRecovery_returnsNilWhenNoFullCycle() {
        let snapshots = [
            snapshot(offsetSeconds: 0, stressScore: 0.8),
            snapshot(offsetSeconds: 10, stressScore: 0.75)
        ]
        XCTAssertNil(evaluator.fastestRecovery(in: snapshots))
    }

    func test_fastestRecovery_picksTheFasterOfTwoRecoveries() {
        let snapshots = [
            snapshot(offsetSeconds: 0, stressScore: 0.8),   // peak #1
            snapshot(offsetSeconds: 5, stressScore: 0.75),  // still peaked
            snapshot(offsetSeconds: 10, stressScore: 0.2),  // recovers in 10s
            snapshot(offsetSeconds: 20, stressScore: 0.8),  // peak #2
            snapshot(offsetSeconds: 25, stressScore: 0.1)   // recovers in 5s
        ]
        XCTAssertEqual(evaluator.fastestRecovery(in: snapshots), 5)
    }

    // MARK: - progress: completeSession

    func test_progress_completeSession_computesFractionAndStatusText() {
        let goal = Goal(kind: .completeSession(minimumSeconds: 300), title: "t", subtitle: "s")
        let facts = SessionFacts(durationSeconds: 150, peakStress: 0, longestCalmRunSeconds: 0, fastestRecoverySeconds: nil, day: base)
        let progress = evaluator.progress(for: goal, facts: facts, activeDaysThisWeek: 0, breathingThisWeek: 0)
        XCTAssertEqual(progress.fraction, 0.5, accuracy: 0.0001)
        XCTAssertEqual(progress.statusText, "02:30 of 05:00")
        XCTAssertFalse(progress.isComplete)
    }

    func test_progress_completeSession_targetIsClampedToMaximumGoalSessionSeconds() {
        // Requesting a full hour is clamped to the 30-minute ceiling, so
        // exactly 30 minutes of actual duration already completes it.
        let goal = Goal(kind: .completeSession(minimumSeconds: 3600), title: "t", subtitle: "s")
        let facts = SessionFacts(durationSeconds: 1800, peakStress: 0, longestCalmRunSeconds: 0, fastestRecoverySeconds: nil, day: base)
        let progress = evaluator.progress(for: goal, facts: facts, activeDaysThisWeek: 0, breathingThisWeek: 0)
        XCTAssertEqual(progress.fraction, 1.0, accuracy: 0.0001)
        XCTAssertTrue(progress.isComplete)
    }

    func test_progress_completeSession_withNoFacts_isZero() {
        let goal = Goal(kind: .completeSession(minimumSeconds: 300), title: "t", subtitle: "s")
        let progress = evaluator.progress(for: goal, facts: nil, activeDaysThisWeek: 0, breathingThisWeek: 0)
        XCTAssertEqual(progress.fraction, 0)
    }

    // MARK: - progress: completeBreathing

    func test_progress_completeBreathing_computesFractionAndStatusText() {
        let goal = Goal(kind: .completeBreathing(count: 3), title: "t", subtitle: "s")
        let progress = evaluator.progress(for: goal, facts: nil, activeDaysThisWeek: 0, breathingThisWeek: 2)
        XCTAssertEqual(progress.fraction, 2.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(progress.statusText, "2 of 3")
    }

    func test_progress_completeBreathing_overshootIsClampedToOne() {
        let goal = Goal(kind: .completeBreathing(count: 3), title: "t", subtitle: "s")
        let progress = evaluator.progress(for: goal, facts: nil, activeDaysThisWeek: 0, breathingThisWeek: 5)
        XCTAssertEqual(progress.fraction, 1.0, accuracy: 0.0001)
        XCTAssertEqual(progress.statusText, "3 of 3")
    }

    // MARK: - progress: activeDays

    func test_progress_activeDays_computesFractionAndStatusText() {
        let goal = Goal(kind: .activeDays(count: 4), title: "t", subtitle: "s")
        let progress = evaluator.progress(for: goal, facts: nil, activeDaysThisWeek: 3, breathingThisWeek: 0)
        XCTAssertEqual(progress.fraction, 0.75, accuracy: 0.0001)
        XCTAssertEqual(progress.statusText, "3 of 4 days")
    }

    // MARK: - progress: sustainedCalm

    func test_progress_sustainedCalm_computesFractionAndStatusText() {
        let goal = Goal(kind: .sustainedCalm(seconds: 300), title: "t", subtitle: "s")
        let facts = SessionFacts(durationSeconds: 0, peakStress: 0, longestCalmRunSeconds: 150, fastestRecoverySeconds: nil, day: base)
        let progress = evaluator.progress(for: goal, facts: facts, activeDaysThisWeek: 0, breathingThisWeek: 0)
        XCTAssertEqual(progress.fraction, 0.5, accuracy: 0.0001)
        XCTAssertEqual(progress.statusText, "02:30 of 05:00")
    }

    // MARK: - progress: fastRecovery

    func test_progress_fastRecovery_withNoPeakToRecoverFrom_isZeroWithExplanation() {
        let goal = Goal(kind: .fastRecovery(withinSeconds: 60), title: "t", subtitle: "s")
        let facts = SessionFacts(durationSeconds: 0, peakStress: 0, longestCalmRunSeconds: 0, fastestRecoverySeconds: nil, day: base)
        let progress = evaluator.progress(for: goal, facts: facts, activeDaysThisWeek: 0, breathingThisWeek: 0)
        XCTAssertEqual(progress.fraction, 0)
        XCTAssertEqual(progress.statusText, "No peak to recover from")
        XCTAssertFalse(progress.isComplete)
    }

    func test_progress_fastRecovery_fasterThanTarget_isClampedToComplete() {
        let goal = Goal(kind: .fastRecovery(withinSeconds: 60), title: "t", subtitle: "s")
        let facts = SessionFacts(durationSeconds: 0, peakStress: 0, longestCalmRunSeconds: 0, fastestRecoverySeconds: 30, day: base)
        let progress = evaluator.progress(for: goal, facts: facts, activeDaysThisWeek: 0, breathingThisWeek: 0)
        XCTAssertEqual(progress.fraction, 1.0, accuracy: 0.0001)
        XCTAssertEqual(progress.statusText, "30s (target 60s)")
        XCTAssertTrue(progress.isComplete)
    }

    func test_progress_fastRecovery_slowerThanTarget_isPartialCredit() {
        let goal = Goal(kind: .fastRecovery(withinSeconds: 60), title: "t", subtitle: "s")
        let facts = SessionFacts(durationSeconds: 0, peakStress: 0, longestCalmRunSeconds: 0, fastestRecoverySeconds: 120, day: base)
        let progress = evaluator.progress(for: goal, facts: facts, activeDaysThisWeek: 0, breathingThisWeek: 0)
        XCTAssertEqual(progress.fraction, 0.5, accuracy: 0.0001)
        XCTAssertEqual(progress.statusText, "120s (target 60s)")
    }
}
