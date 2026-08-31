import XCTest

final class BaselineCalibratorTests: XCTestCase {

    func testRefusesToFinishBelowMinimumSamples() {
        var calibrator = BaselineCalibrator(config: BaselineCalibrationConfig(targetDuration: 60, minimumSamples: 20))
        let start = Date()
        calibrator.start(at: start)

        for i in 0..<5 {
            calibrator.ingest(pulseBPM: 70, eda: 0.02, breathingRPM: 14)
            _ = i
        }

        XCTAssertNil(calibrator.finish())
    }

    func testComputesMeansFromIngestedSamples() {
        var calibrator = BaselineCalibrator(config: BaselineCalibrationConfig(targetDuration: 60, minimumSamples: 5))
        calibrator.start()

        // Breathing: 12, 14, 16 -> mean 14. EDA: -0.01, 0.03 -> abs mean 0.02.
        calibrator.ingest(pulseBPM: 60, eda: -0.01, breathingRPM: 12)
        calibrator.ingest(pulseBPM: 70, eda: 0.03, breathingRPM: 14)
        calibrator.ingest(pulseBPM: 80, eda: 0.01, breathingRPM: 16)
        calibrator.ingest(pulseBPM: 0, eda: 0.01, breathingRPM: 14)  // pulse=0 dropped, others counted
        calibrator.ingest(pulseBPM: 90, eda: 0.01, breathingRPM: 14)

        guard let baseline = calibrator.finish() else {
            return XCTFail("Expected a baseline with 5 ingested samples")
        }

        XCTAssertEqual(baseline.breathingRestingMean, 14.0, accuracy: 0.0001)
        XCTAssertEqual(baseline.pulseRestingMean, 75.0, accuracy: 0.0001)  // (60+70+80+90)/4, zero dropped
        XCTAssertEqual(baseline.sampleCount, 5)
    }

    func testIgnoresIngestBeforeStart() {
        var calibrator = BaselineCalibrator(config: BaselineCalibrationConfig(targetDuration: 60, minimumSamples: 1))
        calibrator.ingest(pulseBPM: 70, eda: 0.02, breathingRPM: 14)
        XCTAssertNil(calibrator.finish())
    }

    func testProgressAndCompletion() {
        var calibrator = BaselineCalibrator(config: BaselineCalibrationConfig(targetDuration: 10, minimumSamples: 1))
        let start = Date()
        calibrator.start(at: start)

        XCTAssertEqual(calibrator.progress, 0, accuracy: 0.01)
        XCTAssertFalse(calibrator.isComplete)
    }
}

final class StressScoringConfigPersonalizationTests: XCTestCase {

    private func baseline(eda: Double = 0.02, breathing: Double = 14, pulse: Double = 68) -> StressBaseline {
        StressBaseline(
            edaRestingMean: eda,
            breathingRestingMean: breathing,
            pulseRestingMean: pulse,
            sampleCount: 30,
            calibratedAt: Date()
        )
    }

    func testPersonalizedThresholdsScaleWithRestingBaseline() {
        // EDA of 0.05 chosen so its 1.6x scaling (0.08) clears the
        // flooring test below (default 0.08 * 0.5 = 0.04) and actually
        // exercises the scaling path rather than the floor.
        let config = StressScoringConfig.personalized(from: baseline(eda: 0.05, breathing: 14, pulse: 68))

        XCTAssertEqual(config.edaStressThreshold, 0.05 * 1.6, accuracy: 0.0001)
        XCTAssertEqual(config.erraticBreathingThreshold, 14 * 1.5, accuracy: 0.0001)
        XCTAssertEqual(config.pulseNormalizationCeiling, 68 * 1.5, accuracy: 0.0001)
    }

    func testPersonalizedThresholdsAreFlooredForVeryLowBaseline() {
        let fallback = StressScoringConfig.default
        let config = StressScoringConfig.personalized(from: baseline(eda: 0.0001, breathing: 1))

        // A near-zero resting reading shouldn't collapse the threshold to
        // near-zero (which would make the stress factor saturate to 1.0
        // permanently) — it should hit the floor instead.
        XCTAssertEqual(config.edaStressThreshold, fallback.edaStressThreshold * 0.5, accuracy: 0.0001)
        XCTAssertEqual(config.erraticBreathingThreshold, fallback.erraticBreathingThreshold * 0.5, accuracy: 0.0001)
    }

    func testPersonalizedConfigProducesSensibleScoreAtOwnRestingLevel() {
        // A person whose resting EDA/breathing exactly match their own
        // baseline should score meaningfully below "critical" — the
        // whole point of personalization is that "normal for me" isn't
        // treated as high stress.
        let personalBaseline = baseline(eda: 0.02, breathing: 14, pulse: 68)
        let engine = StressScoringEngine(config: .personalized(from: personalBaseline))

        let score = engine.stressScore(eda: 0.02, breathingRPM: 14)
        XCTAssertNotNil(score)
        XCTAssertLessThan(score!, 0.7)
    }

    func testMissingPulseBaselineFallsBackToDefaultCeiling() {
        let fallback = StressScoringConfig.default
        let config = StressScoringConfig.personalized(from: baseline(pulse: 0))
        XCTAssertEqual(config.pulseNormalizationCeiling, fallback.pulseNormalizationCeiling)
    }
}
