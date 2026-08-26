import XCTest
@testable import smartspectra_swift_ui

final class InterventionAlertPolicyTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_000_000)

    private func risingForecast(
        score: Double = 0.6,
        confidence: Double = 0.6,
        etaSeconds: TimeInterval? = 120
    ) -> StressForecast {
        StressForecast(
            currentScore: score,
            direction: .rising,
            slopePerSecond: 0.001,
            confidence: confidence,
            timeToThreshold: etaSeconds,
            sampleCount: 10
        )
    }

    // MARK: - Gating conditions

    func test_evaluate_returnsNilWhenInterventionAlreadyActive() {
        var policy = InterventionAlertPolicy()
        let alert = policy.evaluate(risingForecast(), now: base, interventionAlreadyActive: true)
        XCTAssertNil(alert)
    }

    func test_evaluate_returnsNilWhenNotRising() {
        var policy = InterventionAlertPolicy()
        let steady = StressForecast(currentScore: 0.6, direction: .steady, slopePerSecond: 0, confidence: 0.6, timeToThreshold: 120, sampleCount: 10)
        XCTAssertNil(policy.evaluate(steady, now: base, interventionAlreadyActive: false))
    }

    func test_evaluate_returnsNilWhenScoreBelowMinimum() {
        var policy = InterventionAlertPolicy()
        let alert = policy.evaluate(risingForecast(score: 0.3), now: base, interventionAlreadyActive: false)
        XCTAssertNil(alert)
    }

    func test_evaluate_returnsNilWhenConfidenceTooLow() {
        var policy = InterventionAlertPolicy()
        let alert = policy.evaluate(risingForecast(confidence: 0.1), now: base, interventionAlreadyActive: false)
        XCTAssertNil(alert)
    }

    func test_evaluate_returnsNilWhenNoTimeToThreshold() {
        var policy = InterventionAlertPolicy()
        let alert = policy.evaluate(risingForecast(etaSeconds: nil), now: base, interventionAlreadyActive: false)
        XCTAssertNil(alert)
    }

    func test_evaluate_returnsNilWhenEtaBeyondHorizon() {
        var policy = InterventionAlertPolicy()
        // Default horizon is 4 minutes; 10 minutes out has no urgency yet.
        let alert = policy.evaluate(risingForecast(etaSeconds: 600), now: base, interventionAlreadyActive: false)
        XCTAssertNil(alert)
    }

    // MARK: - Raising an alert

    func test_evaluate_raisesRisingTrendAlertWhenConditionsAreMet() {
        var policy = InterventionAlertPolicy()
        let alert = policy.evaluate(risingForecast(etaSeconds: 120), now: base, interventionAlreadyActive: false)
        XCTAssertEqual(alert?.kind, .risingTrend(etaSeconds: 120))
        XCTAssertEqual(alert?.title, "Stress is climbing")
    }

    // MARK: - Cooldown

    func test_evaluate_suppressesASecondAlertWithinCooldown() {
        var policy = InterventionAlertPolicy()
        let first = policy.evaluate(risingForecast(), now: base, interventionAlreadyActive: false)
        XCTAssertNotNil(first)

        // Default cooldown is 5 minutes; 1 minute later is still inside it.
        let second = policy.evaluate(risingForecast(), now: base.addingTimeInterval(60), interventionAlreadyActive: false)
        XCTAssertNil(second)
    }

    func test_evaluate_allowsAnotherAlertOnceCooldownElapses() {
        var policy = InterventionAlertPolicy()
        _ = policy.evaluate(risingForecast(), now: base, interventionAlreadyActive: false)

        // Score must still be *rising* and hasn't recovered enough to
        // count as "recovered" first, so it falls through to the cooldown
        // check on the rising path.
        let later = base.addingTimeInterval(AlertPolicyConfig.default.cooldown + 1)
        let second = policy.evaluate(risingForecast(), now: later, interventionAlreadyActive: false)
        XCTAssertNotNil(second)
    }

    // MARK: - Recovery

    func test_evaluate_raisesRecoveredAlertOnceStressDropsEnoughFromPeak() {
        var policy = InterventionAlertPolicy()
        _ = policy.evaluate(risingForecast(score: 0.6), now: base, interventionAlreadyActive: false)

        // Default recovery delta is 0.25 — dropping from 0.6 to 0.3 clears it.
        let falling = StressForecast(currentScore: 0.3, direction: .falling, slopePerSecond: -0.001, confidence: 0.6, timeToThreshold: nil, sampleCount: 10)
        let recovery = policy.evaluate(falling, now: base.addingTimeInterval(30), interventionAlreadyActive: false)
        XCTAssertEqual(recovery?.kind, .recovered)
    }

    func test_evaluate_doesNotRaiseRecoveredAlertBeforeThresholdIsCleared() {
        var policy = InterventionAlertPolicy()
        _ = policy.evaluate(risingForecast(score: 0.6), now: base, interventionAlreadyActive: false)

        // Only dropped to 0.45 — short of the 0.25 recovery delta from 0.6.
        let stillElevated = StressForecast(currentScore: 0.45, direction: .falling, slopePerSecond: -0.001, confidence: 0.6, timeToThreshold: nil, sampleCount: 10)
        let result = policy.evaluate(stillElevated, now: base.addingTimeInterval(30), interventionAlreadyActive: false)
        XCTAssertNil(result)
    }

    // MARK: - Reset

    func test_reset_clearsCooldownAndAwaitingRecoveryState() {
        var policy = InterventionAlertPolicy()
        _ = policy.evaluate(risingForecast(), now: base, interventionAlreadyActive: false)
        policy.reset()

        // Immediately after reset, a fresh qualifying forecast should
        // raise a new alert rather than being blocked by the prior
        // cooldown or an unresolved "awaiting recovery" state.
        let alert = policy.evaluate(risingForecast(), now: base, interventionAlreadyActive: false)
        XCTAssertNotNil(alert)
    }
}
