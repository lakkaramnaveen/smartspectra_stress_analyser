import XCTest

/// Tests for the stress-trend/prediction module (`swift_ui/forecast/`).
///
/// This target compiles the pure-logic sources directly (`RollingBuffer`,
/// `DomainModels`, `StressForecast`, `StressTrendAnalyzer`,
/// `InterventionAlertPolicy` are all members of both the app target and
/// this one) rather than hosting inside the app binary. The app now gates
/// its window behind Touch ID/passcode (`AppLockService`), so an
/// app-hosted test bundle would hang waiting on an authentication prompt
/// nothing can answer in a non-interactive `xcodebuild test` run — these
/// pure-math types don't need the app running at all.
final class StressTrendAnalyzerTests: XCTestCase {

    func testDetectsRisingTrend() {
        var analyzer = StressTrendAnalyzer()
        let start = Date()

        // Climb 0.30 → 0.60 over 60 samples at 1Hz.
        var forecast = StressForecast.empty
        for i in 0..<60 {
            forecast = analyzer.ingest(
                score: 0.30 + Double(i) * 0.005,
                at: start.addingTimeInterval(Double(i))
            )
        }

        XCTAssertEqual(forecast.direction, .rising)
        XCTAssertGreaterThan(forecast.slopePerSecond, 0)
        XCTAssertGreaterThan(forecast.confidence, 0.95)  // near-perfect line
        XCTAssertNotNil(forecast.timeToThreshold)
    }

    func testFlatSeriesReportsSteady() {
        var analyzer = StressTrendAnalyzer()
        let start = Date()

        var forecast = StressForecast.empty
        for i in 0..<40 {
            forecast = analyzer.ingest(score: 0.5, at: start.addingTimeInterval(Double(i)))
        }

        XCTAssertEqual(forecast.direction, .steady)
        XCTAssertNil(forecast.timeToThreshold)
    }

    func testRefusesToForecastBelowMinimumSamples() {
        var analyzer = StressTrendAnalyzer()
        let forecast = analyzer.ingest(score: 0.8)

        XCTAssertEqual(forecast.direction, .insufficientData)
        XCTAssertNil(forecast.timeToThreshold)
    }

    func testNoisyDataSuppressesETA() {
        var analyzer = StressTrendAnalyzer()
        let start = Date()

        // Wild oscillation with no real trend — slope may be nonzero but
        // R² should be far too low to extrapolate from.
        var forecast = StressForecast.empty
        for i in 0..<60 {
            let noisy = i % 2 == 0 ? 0.2 : 0.9
            forecast = analyzer.ingest(score: noisy, at: start.addingTimeInterval(Double(i)))
        }

        XCTAssertLessThan(forecast.confidence, 0.35)
        XCTAssertNil(forecast.timeToThreshold)
    }
}

final class InterventionAlertPolicyTests: XCTestCase {

    private func risingForecast(score: Double = 0.6, eta: TimeInterval = 120) -> StressForecast {
        StressForecast(
            currentScore: score,
            direction: .rising,
            slopePerSecond: 0.002,
            confidence: 0.8,
            timeToThreshold: eta,
            sampleCount: 60
        )
    }

    func testRaisesAlertForCredibleRisingTrend() {
        var policy = InterventionAlertPolicy()
        let alert = policy.evaluate(risingForecast(), interventionAlreadyActive: false)
        XCTAssertNotNil(alert)
    }

    func testSuppressesDuringActiveIntervention() {
        var policy = InterventionAlertPolicy()
        let alert = policy.evaluate(risingForecast(), interventionAlreadyActive: true)
        XCTAssertNil(alert)
    }

    func testRespectsCooldown() {
        var policy = InterventionAlertPolicy()
        let now = Date()

        XCTAssertNotNil(policy.evaluate(risingForecast(), now: now, interventionAlreadyActive: false))

        // 60s later — well inside the 5-minute cooldown.
        let second = policy.evaluate(
            risingForecast(),
            now: now.addingTimeInterval(60),
            interventionAlreadyActive: false
        )
        XCTAssertNil(second)
    }

    func testIgnoresLowStressEvenWhenRising() {
        var policy = InterventionAlertPolicy()
        let alert = policy.evaluate(
            risingForecast(score: 0.15),
            interventionAlreadyActive: false
        )
        XCTAssertNil(alert)
    }
}
