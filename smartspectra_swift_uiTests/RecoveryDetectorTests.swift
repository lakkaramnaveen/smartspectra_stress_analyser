import XCTest
@testable import smartspectra_swift_ui

final class RecoveryDetectorTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 0)

    private func time(_ offsetSeconds: Double) -> Date {
        base.addingTimeInterval(offsetSeconds)
    }

    // MARK: - No episode

    func test_ingest_belowPeakThreshold_staysIdle() {
        var detector = RecoveryDetector()
        XCTAssertEqual(detector.ingest(score: 0.2, now: time(0)), .idle)
        XCTAssertEqual(detector.ingest(score: 0.3, now: time(1)), .idle)
    }

    // MARK: - Full arc: peak -> unconfirmed descent -> easing -> settling -> settled

    func test_ingest_tracksTheFullRecoveryArc() {
        var detector = RecoveryDetector()

        // Peak episode begins; still idle while the reading itself is
        // at/above the peak threshold, however it moves.
        XCTAssertEqual(detector.ingest(score: 0.9, now: time(0)), .idle)

        // Once below the peak threshold, each descending sample needs to
        // accumulate `confirmationSamples` (4, default) before a descent
        // is confirmed and the episode starts reporting anything.
        XCTAssertEqual(detector.ingest(score: 0.70, now: time(1)), .idle)
        XCTAssertEqual(detector.ingest(score: 0.65, now: time(2)), .idle)
        XCTAssertEqual(detector.ingest(score: 0.60, now: time(3)), .idle)

        // 4th consecutive descending sample confirms it.
        guard case .recovering(let easing) = detector.ingest(score: 0.55, now: time(4)) else {
            return XCTFail("expected a confirmed recovering state")
        }
        XCTAssertEqual(easing.phase, .easing)
        XCTAssertEqual(easing.peakScore, 0.9, accuracy: 0.0001)

        // Closer to baseline (default assumed baseline is 0.30): crosses
        // into the "settling" band.
        guard case .recovering(let settling) = detector.ingest(score: 0.45, now: time(5)) else {
            return XCTFail("expected a recovering state")
        }
        XCTAssertEqual(settling.phase, .settling)

        // Within `settledTolerance` (0.08, default) of baseline: settled.
        guard case .settled(let settled) = detector.ingest(score: 0.35, now: time(6)) else {
            return XCTFail("expected a settled state")
        }
        XCTAssertEqual(settled.phase, .settled)
    }

    func test_ingest_afterSettled_startsFreshWithNoLingeringPeak() {
        var detector = RecoveryDetector()
        _ = detector.ingest(score: 0.9, now: time(0))
        _ = detector.ingest(score: 0.70, now: time(1))
        _ = detector.ingest(score: 0.65, now: time(2))
        _ = detector.ingest(score: 0.60, now: time(3))
        _ = detector.ingest(score: 0.55, now: time(4))
        _ = detector.ingest(score: 0.45, now: time(5))
        _ = detector.ingest(score: 0.35, now: time(6)) // settled, episode ends

        // With no active peak, even a low reading is just idle again —
        // not, say, an immediate re-triggered recovery.
        XCTAssertEqual(detector.ingest(score: 0.32, now: time(7)), .idle)
    }

    func test_ingest_climbingAgainResetsDescentConfirmation() {
        var detector = RecoveryDetector()
        _ = detector.ingest(score: 0.9, now: time(0))
        _ = detector.ingest(score: 0.70, now: time(1)) // descendingRun = 1
        _ = detector.ingest(score: 0.65, now: time(2)) // descendingRun = 2

        // A real climb (not just noise) resets the confirmation count —
        // the next three descending samples alone shouldn't be enough.
        _ = detector.ingest(score: 0.72, now: time(3))
        XCTAssertEqual(detector.ingest(score: 0.68, now: time(4)), .idle)
        XCTAssertEqual(detector.ingest(score: 0.64, now: time(5)), .idle)
        XCTAssertEqual(detector.ingest(score: 0.60, now: time(6)), .idle)
    }

    // MARK: - Baseline: assumed default

    func test_baseline_withNoHistoryAndFewCalmSamples_isTheAssumedDefault() {
        let detector = RecoveryDetector()
        XCTAssertEqual(detector.baseline, .assumedDefault)
    }

    // MARK: - Baseline: derived from in-session calm samples

    func test_baseline_derivedFromCalmSampleMedianOnceEnoughAccumulate() {
        var detector = RecoveryDetector()
        for i in 0..<30 {
            _ = detector.ingest(score: 0.2, now: time(Double(i)))
        }
        XCTAssertEqual(detector.baseline.value, 0.2, accuracy: 0.0001)
        XCTAssertEqual(detector.baseline.source, .currentSession)
    }

    func test_reset_clearsTheCalmSampleBaselineEstimate() {
        var detector = RecoveryDetector()
        for i in 0..<30 {
            _ = detector.ingest(score: 0.2, now: time(Double(i)))
        }
        detector.reset()
        XCTAssertEqual(detector.baseline, .assumedDefault)
    }

    // MARK: - Baseline: historical override

    func test_baseline_confidentHistoricalBaselineTakesPrecedenceOverCalmSamples() {
        var detector = RecoveryDetector()
        for i in 0..<30 {
            _ = detector.ingest(score: 0.2, now: time(Double(i)))
        }
        let historical = StressBaseline(value: 0.45, sampleCount: 50, source: .history)
        detector.setHistoricalBaseline(historical)

        XCTAssertEqual(detector.baseline, historical)
    }

    func test_baseline_unconfidentHistoricalBaselineIsStillUsedOverTheAssumedDefault() {
        var detector = RecoveryDetector()
        // Not enough samples to be "confident" yet, but still real data —
        // preferred over the assumed default when there's nothing better.
        let unconfident = StressBaseline(value: 0.5, sampleCount: 5, source: .history)
        XCTAssertFalse(unconfident.isConfident)
        detector.setHistoricalBaseline(unconfident)

        XCTAssertEqual(detector.baseline, unconfident)
    }
}
