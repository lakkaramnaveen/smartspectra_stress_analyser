import XCTest
@testable import smartspectra_swift_ui

final class CorrelationAnalyzerTests: XCTestCase {

    // MARK: - pearson

    func test_pearson_returnsNilForFewerThanThreePairs() {
        XCTAssertNil(CorrelationAnalyzer.pearson([1, 2], [1, 2]))
    }

    func test_pearson_returnsNilForMismatchedLengths() {
        XCTAssertNil(CorrelationAnalyzer.pearson([1, 2, 3], [1, 2]))
    }

    func test_pearson_returnsNilWhenXIsConstant() {
        // Zero variance means there's nothing to correlate, not a
        // correlation of zero.
        XCTAssertNil(CorrelationAnalyzer.pearson([5, 5, 5], [1, 2, 3]))
    }

    func test_pearson_returnsNilWhenYIsConstant() {
        XCTAssertNil(CorrelationAnalyzer.pearson([1, 2, 3], [5, 5, 5]))
    }

    func test_pearson_isOneForPerfectPositiveCorrelation() {
        let r = CorrelationAnalyzer.pearson([1, 2, 3, 4, 5], [2, 4, 6, 8, 10])
        XCTAssertEqual(r ?? -99, 1.0, accuracy: 0.0001)
    }

    func test_pearson_isNegativeOneForPerfectNegativeCorrelation() {
        let r = CorrelationAnalyzer.pearson([1, 2, 3, 4, 5], [10, 8, 6, 4, 2])
        XCTAssertEqual(r ?? -99, -1.0, accuracy: 0.0001)
    }

    func test_pearson_isSymmetric() {
        let xs = [1.0, 2.0, 3.0, 4.0]
        let ys = [2.0, 1.0, 4.0, 3.0]
        XCTAssertEqual(CorrelationAnalyzer.pearson(xs, ys), CorrelationAnalyzer.pearson(ys, xs))
    }

    // MARK: - bestLead

    func test_bestLead_findsTheCorrectLag() {
        // `leading` is deliberately irregular (no monotonic trend, no
        // periodicity) so that only the correctly-aligned lag produces a
        // strong correlation — a monotonic series would correlate
        // strongly at *every* lag and couldn't isolate the right one.
        // `following` is `leading` delayed by exactly 3 samples, padded
        // with zeros before the delay kicks in.
        let leading: [Double] = [3, 1, 4, 1, 5, 9, 2, 6, 5, 3, 5, 8]
        let following: [Double] = [0, 0, 0] + leading.prefix(9)

        let result = CorrelationAnalyzer.bestLead(leading: leading, following: following, maxLagSamples: 5)
        XCTAssertEqual(result?.lagSamples, 3)
        XCTAssertEqual(result?.correlation ?? -99, 1.0, accuracy: 0.0001)
    }

    func test_bestLead_returnsNilWhenSeriesTooShortForMaxLag() {
        let short = [1.0, 2.0, 3.0, 4.0]
        XCTAssertNil(CorrelationAnalyzer.bestLead(leading: short, following: short, maxLagSamples: 2))
    }

    func test_bestLead_returnsNilWhenMaxLagIsZero() {
        let series = (1...20).map(Double.init)
        XCTAssertNil(CorrelationAnalyzer.bestLead(leading: series, following: series, maxLagSamples: 0))
    }

    func test_bestLead_returnsNilForMismatchedLengths() {
        let leading = (1...20).map(Double.init)
        let following = (1...19).map(Double.init)
        XCTAssertNil(CorrelationAnalyzer.bestLead(leading: leading, following: following, maxLagSamples: 3))
    }

    // MARK: - strengthLabel

    func test_strengthLabel_bandsMatchConventionalThresholds() {
        XCTAssertEqual(CorrelationAnalyzer.strengthLabel(for: 0.1), "little")
        XCTAssertEqual(CorrelationAnalyzer.strengthLabel(for: 0.2), "a weak")
        XCTAssertEqual(CorrelationAnalyzer.strengthLabel(for: 0.3), "a weak")
        XCTAssertEqual(CorrelationAnalyzer.strengthLabel(for: 0.4), "a moderate")
        XCTAssertEqual(CorrelationAnalyzer.strengthLabel(for: 0.5), "a moderate")
        XCTAssertEqual(CorrelationAnalyzer.strengthLabel(for: 0.6), "a strong")
        XCTAssertEqual(CorrelationAnalyzer.strengthLabel(for: 0.7), "a strong")
        XCTAssertEqual(CorrelationAnalyzer.strengthLabel(for: 0.8), "a very strong")
        XCTAssertEqual(CorrelationAnalyzer.strengthLabel(for: 0.95), "a very strong")
    }

    func test_strengthLabel_usesAbsoluteValueForNegativeCorrelations() {
        XCTAssertEqual(CorrelationAnalyzer.strengthLabel(for: -0.9), "a very strong")
    }
}
