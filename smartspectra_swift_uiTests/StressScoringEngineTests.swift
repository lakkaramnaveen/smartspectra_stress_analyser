import XCTest
@testable import smartspectra_swift_ui

final class StressScoringEngineTests: XCTestCase {

    private let engine = StressScoringEngine()

    // MARK: - stressScore

    func test_stressScore_returnsNilWhenBreathingIsZero() {
        XCTAssertNil(engine.stressScore(eda: 0.05, breathingRPM: 0))
    }

    func test_stressScore_returnsNilWhenBreathingIsNegative() {
        XCTAssertNil(engine.stressScore(eda: 0.05, breathingRPM: -1))
    }

    func test_stressScore_averagesEdaAndBreathingFactors() {
        // eda at half its threshold (0.08), breathing at half its threshold
        // (22) — each factor should land at 0.5, averaging to 0.5.
        let score = engine.stressScore(eda: 0.04, breathingRPM: 11)
        XCTAssertEqual(score ?? -1, 0.5, accuracy: 0.0001)
    }

    func test_stressScore_clampsBothFactorsAtOne() {
        let score = engine.stressScore(eda: 10, breathingRPM: 1000)
        XCTAssertEqual(score ?? -1, 1.0, accuracy: 0.0001)
    }

    func test_stressScore_usesAbsoluteValueOfEda() {
        let positive = engine.stressScore(eda: 0.04, breathingRPM: 11)
        let negative = engine.stressScore(eda: -0.04, breathingRPM: 11)
        XCTAssertEqual(positive, negative)
    }

    func test_stressScore_respectsCustomConfig() {
        let lenient = StressScoringEngine(config: StressScoringConfig(edaStressThreshold: 1.0))
        // With a threshold of 1.0, the same eda that saturated the factor
        // above now only contributes a fraction.
        let score = lenient.stressScore(eda: 0.04, breathingRPM: 11)
        XCTAssertEqual(score ?? -1, (0.04 + 0.5) / 2, accuracy: 0.0001)
    }

    // MARK: - emotionalState

    /// Pulse, EDA, and breathing are each normalized against their own
    /// ceiling, so scaling all three by the same fraction `x` of their
    /// ceilings makes the resulting intensity exactly `x` — a
    /// straightforward way to hit every classification boundary.
    private func emotionalIntensityInputs(fraction: Double) -> (pulse: Double, eda: Double, breathing: Double) {
        (pulse: fraction * 120.0, eda: fraction * 0.1, breathing: fraction * 25.0)
    }

    func test_emotionalState_classifiesCalmBelow0_3() {
        let inputs = emotionalIntensityInputs(fraction: 0.0)
        let result = engine.emotionalState(pulseBPM: inputs.pulse, eda: inputs.eda, breathingRPM: inputs.breathing)
        XCTAssertEqual(result.state, .calm)
        XCTAssertEqual(result.intensity, 0.0, accuracy: 0.0001)
    }

    func test_emotionalState_classifiesFocusedBetween0_3And0_5() {
        let inputs = emotionalIntensityInputs(fraction: 0.4)
        let result = engine.emotionalState(pulseBPM: inputs.pulse, eda: inputs.eda, breathingRPM: inputs.breathing)
        XCTAssertEqual(result.state, .focused)
    }

    func test_emotionalState_classifiesAnxiousBetween0_5And0_7() {
        let inputs = emotionalIntensityInputs(fraction: 0.6)
        let result = engine.emotionalState(pulseBPM: inputs.pulse, eda: inputs.eda, breathingRPM: inputs.breathing)
        XCTAssertEqual(result.state, .anxious)
    }

    func test_emotionalState_classifiesStressedAt0_7AndAbove() {
        let inputs = emotionalIntensityInputs(fraction: 0.8)
        let result = engine.emotionalState(pulseBPM: inputs.pulse, eda: inputs.eda, breathingRPM: inputs.breathing)
        XCTAssertEqual(result.state, .stressed)
    }

    func test_emotionalState_clampsEachFactorIndependently() {
        // Pulse alone saturated, EDA and breathing at zero — intensity
        // should reflect only the one contributing factor (1/3), not
        // overflow from the saturated pulse term.
        let result = engine.emotionalState(pulseBPM: 500, eda: 0, breathingRPM: 0)
        XCTAssertEqual(result.intensity, 1.0 / 3.0, accuracy: 0.0001)
    }

    // MARK: - shouldTriggerIntervention

    func test_shouldTriggerIntervention_falseAtDefaultThreshold() {
        XCTAssertFalse(engine.shouldTriggerIntervention(forStressScore: 0.95))
        XCTAssertFalse(engine.shouldTriggerIntervention(forStressScore: 0.94))
    }

    func test_shouldTriggerIntervention_trueAboveDefaultThreshold() {
        XCTAssertTrue(engine.shouldTriggerIntervention(forStressScore: 0.96))
    }

    func test_shouldTriggerIntervention_respectsCustomThreshold() {
        let sensitive = StressScoringEngine(config: StressScoringConfig(extremeStressThreshold: 0.5))
        XCTAssertTrue(sensitive.shouldTriggerIntervention(forStressScore: 0.6))
        XCTAssertFalse(sensitive.shouldTriggerIntervention(forStressScore: 0.4))
    }
}
