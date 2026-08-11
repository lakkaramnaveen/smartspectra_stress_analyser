# Wellness Goals & Streaks — Integration Guide

Eight files into a new `goals/` group:

```
swift_ui/
├── goals/
│   ├── GoalModels.swift          → Goal, Achievement, StreakState, records
│   ├── GoalEvaluator.swift       → pure session→progress measurement
│   ├── StreakCalculator.swift    → forgiving calendar streak logic
│   ├── AchievementCatalog.swift  → definitions + unlock evaluation
│   ├── GoalsStore.swift          → persistence (protocol + impls)
│   ├── GoalsCoordinator.swift    → MainActor facade AppModel composes
│   ├── ProgressRing.swift        → reusable ring component
│   └── GoalsDashboardView.swift  → dashboard UI
├── insights/
├── prediction/
├── session/
└── ...
```

Depends on Session Recording — streaks and records are derived from
`SessionStoring` history.

---

## 1. Compose the coordinator into `AppModel`

```swift
// AppModel.swift — properties

private let sessionRecorder: SessionRecorder
let prediction: StressPredictionCoordinator
let goals: GoalsCoordinator          // ← add (not private: views read it)
```

```swift
// AppModel.swift — init

init(
    engine: BiometricEngineProviding = BiometricEngine(),
    credentialStore: CredentialStoring = KeychainCredentialStore(),
    scoringEngine: StressScoringEngine = StressScoringEngine(),
    sessionRecorder: SessionRecorder? = nil,
    prediction: StressPredictionCoordinator? = nil,
    goals: GoalsCoordinator? = nil                        // ← add, nil-defaulted
) {
    ...
    self.goals = goals ?? GoalsCoordinator()              // ← add
}
```

Nil-defaulted for the same reason as the previous two coordinators:
default-argument expressions evaluate non-isolated, which trips
`@MainActor` checking.

## 2. Refresh goals when a session ends

`SessionRecorder.stop()` already returns the finished recording, so pass
it straight through:

```swift
// AppModel.swift — stop()

func stop() {
    engine.stop()
    isRunning = false
    processingStatus = "stopped"
    isBiofeedbackActive = false
    stopGame()
    stopSessionTimer()

    let finished = sessionRecorder.stop()                 // ← capture it
    goals.refresh(latestSession: finished)                // ← add
}
```

## 3. Count completed breathing exercises

In `BreathingPacerView.swift`, where the six cycles finish:

```swift
// performBreathCycle() — the cycleCount >= 6 branch

if cycleCount >= 6 {
    model.goals.recordBreathingCompleted()                // ← add
    stopBreathing()
} else {
    performBreathCycle()
}
```

Note this fires on *completion*, not on the pacer appearing — a user who
dismisses the breathing overlay after four seconds hasn't taken a
breathing break, and counting it would make the achievement meaningless.

## 4. Add the tab

`ContentView.swift`:

```swift
enum SidebarTab: String, CaseIterable {
    case controls, stress, emotions, game, history, insights, goals   // ← add

    var icon: String {
        switch self {
        ...
        case .goals: return "target"                                   // ← add
        }
    }
}
```

```swift
// sidebarContent
case .goals:
    GoalsDashboardView(coordinator: model.goals)
```

---

## Design notes

Gamifying a *stress* metric has a specific failure mode: users become
stressed about the streak. Three constraints are enforced in code rather
than left to good intentions.

**Process goals outweigh outcome goals, 3:1.** `GoalKind.isOutcomeBased`
marks goals whose result is partly outside the user's control
(`sustainedCalm`, `fastRecovery`). Those are the minority, they're
excluded from streak eligibility, and they're never framed as pass/fail.
Rewarding only low readings means punishing someone for a bad meeting or
a poor night's sleep — unfair, and it drives people to skip the app
precisely on the days it would help most.

**Streaks survive a missed day.** `StreakCalculator` carries a grace day
that replenishes weekly, and the dashboard says so explicitly — an
invisible safety net doesn't reduce pressure, because reducing pressure
requires the user to know it's there. Streak copy uses no loss framing:
a lapsed streak reads "starting fresh," never "you lost 12 days."

**Nothing rewards a low reading directly.** There is deliberately no
"lowest stress score" achievement. Rewarding a low number incentivises
gaming the sensor — sitting rigidly still, holding your breath, skipping
sessions on hard days — none of which is wellness. Achievements reward
consistency and use of the interventions instead.

**Session-length goals are capped.**
`GoalEvaluationConfig.maximumGoalSessionSeconds` clamps any goal asking
for more than 30 minutes. A "record a four-hour session" goal would be
one line to add and would reward compulsive self-monitoring.

**Records are history, not targets.** The UI says so directly. A user
treating "lowest peak stress ever" as a bar to clear each session has
converted a keepsake into a pressure source.

**Unlocks are recomputed, not incremented.**
`AchievementCatalog.earnedIDs` is pure and idempotent; the coordinator
diffs it against stored unlocks. A partially-written unlock list
self-heals on next evaluation rather than leaving something permanently
unearnable. Achievements are also measured against `streak.best`, so a
lapsed streak never revokes something already earned.

---

## Tests

```swift
import XCTest

final class StreakCalculatorTests: XCTestCase {

    private let calendar = Calendar.current

    private func days(agoFrom today: Date, _ offsets: [Int]) -> Set<Date> {
        Set(offsets.compactMap {
            calendar.date(byAdding: .day, value: -$0, to: today)
                .map { calendar.startOfDay(for: $0) }
        })
    }

    func testConsecutiveDaysBuildStreak() {
        let today = Date()
        let state = StreakCalculator().streak(
            from: days(agoFrom: today, [0, 1, 2, 3]),
            asOf: today
        )
        XCTAssertEqual(state.current, 4)
        XCTAssertEqual(state.best, 4)
    }

    func testSingleMissedDayDoesNotBreakStreak() {
        // Missing day 2 entirely — grace should absorb it.
        let today = Date()
        let state = StreakCalculator().streak(
            from: days(agoFrom: today, [0, 1, 3, 4]),
            asOf: today
        )
        XCTAssertGreaterThan(state.current, 0, "One missed day must not reset the streak")
    }

    func testTodayNotYetLoggedKeepsStreakAlive() {
        // Last session was yesterday; today isn't over yet.
        let today = Date()
        let state = StreakCalculator().streak(
            from: days(agoFrom: today, [1, 2, 3]),
            asOf: today
        )
        XCTAssertEqual(state.current, 3)
    }

    func testLongGapResetsCurrentButKeepsBest() {
        let today = Date()
        let state = StreakCalculator().streak(
            from: days(agoFrom: today, [30, 31, 32, 33, 34]),
            asOf: today
        )
        XCTAssertEqual(state.current, 0)
        XCTAssertEqual(state.best, 5, "Best must survive a lapse")
    }
}

final class GoalEvaluatorTests: XCTestCase {

    private func snapshots(_ scores: [Double], start: Date = Date()) -> [SessionSnapshot] {
        scores.enumerated().map { index, score in
            SessionSnapshot(
                timestamp: start.addingTimeInterval(Double(index)),
                stressScore: score,
                heartRate: 70,
                breathingRate: 14,
                eda: 0.02,
                emotionalState: "Calm",
                gazeConfidence: 0.9
            )
        }
    }

    func testLongestCalmRunMeasuresElapsedTime() {
        // 30 calm samples at 1s spacing = ~29s run.
        let evaluator = GoalEvaluator()
        let run = evaluator.longestCalmRun(in: snapshots(Array(repeating: 0.2, count: 30)))
        XCTAssertEqual(run, 29, accuracy: 1.0)
    }

    func testCalmRunClosesAtSessionEnd() {
        // Session ends while still calm — the final stretch must count.
        let evaluator = GoalEvaluator()
        let scores = Array(repeating: 0.8, count: 5) + Array(repeating: 0.2, count: 20)
        let run = evaluator.longestCalmRun(in: snapshots(scores))
        XCTAssertGreaterThan(run, 15)
    }

    func testIncompleteRecoveryReturnsNilNotInfinity() {
        // Peaks and never comes back down.
        let evaluator = GoalEvaluator()
        let scores = Array(repeating: 0.2, count: 5) + Array(repeating: 0.85, count: 20)
        XCTAssertNil(evaluator.fastestRecovery(in: snapshots(scores)))
    }

    func testSessionGoalIsCappedAgainstCompulsiveTargets() {
        let evaluator = GoalEvaluator()
        // Ask for 4 hours; config caps goal targets at 30 minutes.
        let goal = Goal(
            kind: .completeSession(minimumSeconds: 4 * 3600),
            title: "Marathon",
            subtitle: "Test"
        )
        let facts = SessionFacts(
            durationSeconds: 30 * 60,
            peakStress: 0.5,
            longestCalmRunSeconds: 0,
            fastestRecoverySeconds: nil,
            day: Date()
        )
        let progress = evaluator.progress(
            for: goal, facts: facts, activeDaysThisWeek: 0, breathingThisWeek: 0
        )
        XCTAssertEqual(progress.fraction, 1.0, "30 min must satisfy a capped goal")
    }
}

final class AchievementCatalogTests: XCTestCase {

    func testUnlocksAreIdempotent() {
        var records = PersonalRecords.empty
        records.totalSessions = 30
        let streak = StreakState(current: 0, best: 8, lastQualifyingDay: nil, graceDaysRemaining: 1)

        let first = AchievementCatalog.earnedIDs(streak: streak, records: records)
        let second = AchievementCatalog.earnedIDs(streak: streak, records: records)
        XCTAssertEqual(first, second)
    }

    func testLapsedStreakDoesNotRevokeAchievements() {
        var records = PersonalRecords.empty
        records.totalSessions = 10
        // current == 0, but best == 7
        let streak = StreakState(current: 0, best: 7, lastQualifyingDay: nil, graceDaysRemaining: 1)

        let earned = AchievementCatalog.earnedIDs(streak: streak, records: records)
        XCTAssertTrue(earned.contains("streak.7"))
    }

    func testNoAchievementRewardsLowStressReadings() {
        // Guards the design rule: nothing in the catalog should be
        // earnable by producing a low number, since that incentivises
        // gaming the sensor rather than actual wellbeing.
        var records = PersonalRecords.empty
        records.lowestSessionPeakStress = 0.01
        let earned = AchievementCatalog.earnedIDs(streak: .empty, records: records)
        XCTAssertTrue(earned.isEmpty)
    }
}
```
