import XCTest
@testable import smartspectra_swift_ui

final class LinearFitTests: XCTestCase {

    func test_init_returnsNilForFewerThanTwoPoints() {
        XCTAssertNil(LinearFit(xs: [], ys: []))
        XCTAssertNil(LinearFit(xs: [1], ys: [1]))
    }

    func test_init_returnsNilForMismatchedLengths() {
        XCTAssertNil(LinearFit(xs: [1, 2, 3], ys: [1, 2]))
    }

    func test_init_returnsNilWhenAllXValuesAreIdentical() {
        // A vertical line has no finite slope.
        XCTAssertNil(LinearFit(xs: [5, 5, 5], ys: [1, 2, 3]))
    }

    func test_init_computesExactSlopeAndInterceptForAPerfectLine() {
        let xs = [0.0, 1.0, 2.0, 3.0, 4.0]
        let ys = xs.map { 2 * $0 + 1 }
        let fit = LinearFit(xs: xs, ys: ys)
        XCTAssertEqual(fit?.slope ?? -99, 2.0, accuracy: 0.0001)
        XCTAssertEqual(fit?.intercept ?? -99, 1.0, accuracy: 0.0001)
        XCTAssertEqual(fit?.rSquared ?? -99, 1.0, accuracy: 0.0001)
    }

    func test_init_flatYSeries_hasZeroSlopeAndPerfectFit() {
        // Zero total variance in y is treated as a perfect fit (R² = 1)
        // rather than dividing by zero.
        let fit = LinearFit(xs: [0.0, 1.0, 2.0, 3.0], ys: [5.0, 5.0, 5.0, 5.0])
        XCTAssertEqual(fit?.slope ?? -99, 0.0, accuracy: 0.0001)
        XCTAssertEqual(fit?.rSquared ?? -99, 1.0, accuracy: 0.0001)
    }
}

final class StressTrendAnalyzerTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 0)

    private func makeAnalyzer() -> StressTrendAnalyzer {
        StressTrendAnalyzer()
    }

    /// Ingests one sample per second for `count` seconds, with
    /// `score(t)` computing the value at second `t`. Returns the
    /// forecast from the final ingest.
    @discardableResult
    private func ingestSeries(
        into analyzer: inout StressTrendAnalyzer,
        count: Int,
        score: (Int) -> Double
    ) -> StressForecast {
        var forecast = StressForecast.empty
        for t in 0..<count {
            forecast = analyzer.ingest(score: score(t), at: base.addingTimeInterval(Double(t)))
        }
        return forecast
    }

    // MARK: - Insufficient data

    func test_forecast_withNoSamples_isInsufficientData() {
        let analyzer = makeAnalyzer()
        let forecast = analyzer.forecast()
        XCTAssertEqual(forecast.direction, .insufficientData)
        XCTAssertEqual(forecast.sampleCount, 0)
        XCTAssertEqual(forecast.currentScore, 0)
    }

    func test_forecast_belowMinimumSamples_isInsufficientDataButReportsLatestScore() {
        var analyzer = makeAnalyzer()
        let forecast = ingestSeries(into: &analyzer, count: 5) { 0.1 * Double($0 + 1) }
        XCTAssertEqual(forecast.direction, .insufficientData)
        XCTAssertEqual(forecast.sampleCount, 5)
        XCTAssertEqual(forecast.currentScore, 0.5, accuracy: 0.0001)
    }

    // MARK: - Rising

    func test_forecast_risingTrend_classifiesDirectionAndSlope() {
        var analyzer = makeAnalyzer()
        // Perfectly linear rise: 0.001/sec, well above the steady
        // threshold and with a perfect (R² = 1) fit.
        let forecast = ingestSeries(into: &analyzer, count: 30) { 0.5 + 0.001 * Double($0) }

        XCTAssertEqual(forecast.direction, .rising)
        XCTAssertEqual(forecast.slopePerSecond, 0.001, accuracy: 0.0001)
        XCTAssertEqual(forecast.confidence, 1.0, accuracy: 0.0001)
        XCTAssertEqual(forecast.sampleCount, 30)
    }

    func test_forecast_risingTrend_estimatesTimeToThreshold() {
        var analyzer = makeAnalyzer()
        let forecast = ingestSeries(into: &analyzer, count: 30) { 0.5 + 0.001 * Double($0) }

        // Default intervention threshold is 0.95; last score is
        // 0.5 + 0.001*29 = 0.529, so remaining/slope = 0.421/0.001 = 421s.
        XCTAssertEqual(forecast.timeToThreshold ?? -1, 421, accuracy: 1)
    }

    func test_forecast_risingTrend_beyondHorizon_reportsNoETA() {
        var analyzer = makeAnalyzer()
        // A very shallow rise puts the threshold crossing far beyond the
        // default 15-minute forecast horizon.
        let forecast = ingestSeries(into: &analyzer, count: 30) { 0.1 + 0.0006 * Double($0) }
        XCTAssertEqual(forecast.direction, .rising)
        XCTAssertNil(forecast.timeToThreshold)
    }

    // MARK: - Falling / steady

    func test_forecast_fallingTrend_classifiesDirectionAndHasNoETA() {
        var analyzer = makeAnalyzer()
        let forecast = ingestSeries(into: &analyzer, count: 30) { 0.9 - 0.001 * Double($0) }
        XCTAssertEqual(forecast.direction, .falling)
        XCTAssertLessThan(forecast.slopePerSecond, 0)
        XCTAssertNil(forecast.timeToThreshold)
    }

    func test_forecast_flatSeries_isSteadyWithNoETA() {
        var analyzer = makeAnalyzer()
        let forecast = ingestSeries(into: &analyzer, count: 30) { _ in 0.5 }
        XCTAssertEqual(forecast.direction, .steady)
        XCTAssertNil(forecast.timeToThreshold)
    }

    // MARK: - Reset

    func test_reset_clearsSamplesBackToInsufficientData() {
        var analyzer = makeAnalyzer()
        _ = ingestSeries(into: &analyzer, count: 30) { 0.5 + 0.001 * Double($0) }
        analyzer.reset()

        let forecast = analyzer.forecast()
        XCTAssertEqual(forecast.direction, .insufficientData)
        XCTAssertEqual(forecast.sampleCount, 0)
    }

    // MARK: - Window capacity

    func test_forecast_windowIsBoundedByCapacity() {
        var analyzer = makeAnalyzer()
        // Default window capacity is 120 samples; ingesting more than
        // that should never report a sample count above the cap.
        let forecast = ingestSeries(into: &analyzer, count: 150) { 0.5 + 0.0001 * Double($0) }
        XCTAssertLessThanOrEqual(forecast.sampleCount, 120)
    }
}
