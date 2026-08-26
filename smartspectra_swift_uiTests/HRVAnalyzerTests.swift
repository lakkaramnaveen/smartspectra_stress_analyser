import XCTest
@testable import smartspectra_swift_ui

final class HRVAnalyzerTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 0)

    // MARK: - Static metrics

    func test_rmssd_returnsNilForFewerThanTwoIntervals() {
        XCTAssertNil(HRVAnalyzer.rmssd([800]))
        XCTAssertNil(HRVAnalyzer.rmssd([]))
    }

    func test_rmssd_computesRootMeanSquareOfSuccessiveDifferences() {
        // Successive diffs: 50, -50, 50 -> mean square 2500 -> rmssd 50.
        XCTAssertEqual(HRVAnalyzer.rmssd([800, 850, 800, 850]) ?? -1, 50.0, accuracy: 0.0001)
    }

    func test_sdnn_returnsNilForFewerThanTwoIntervals() {
        XCTAssertNil(HRVAnalyzer.sdnn([800]))
    }

    func test_sdnn_computesStandardDeviation() {
        // Mean 825, each value 25 away from the mean -> sdnn 25.
        XCTAssertEqual(HRVAnalyzer.sdnn([800, 850, 800, 850]) ?? -1, 25.0, accuracy: 0.0001)
    }

    func test_meanBPM_returnsNilForEmptyIntervals() {
        XCTAssertNil(HRVAnalyzer.meanBPM([]))
    }

    func test_meanBPM_returnsNilForNonPositiveMeanInterval() {
        XCTAssertNil(HRVAnalyzer.meanBPM([0, 0]))
    }

    func test_meanBPM_convertsMillisecondsToBeatsPerMinute() {
        // 1000ms intervals -> exactly 60 beats/minute.
        XCTAssertEqual(HRVAnalyzer.meanBPM([1000, 1000]) ?? -1, 60.0, accuracy: 0.0001)
    }

    // MARK: - Ingestion gating

    private func intervals(count: Int, alternatingMs first: Double = 800, second: Double = 850) -> [BeatInterval] {
        (0..<count).map { i in
            BeatInterval(
                milliseconds: i.isMultiple(of: 2) ? first : second,
                timestamp: base.addingTimeInterval(Double(i))
            )
        }
    }

    func test_ingest_returnsNilForUnusableQuality() {
        var analyzer = HRVAnalyzer()
        let reading = analyzer.ingest(intervals: intervals(count: 30), quality: .unusable, artefactRate: 0)
        XCTAssertNil(reading)
    }

    func test_ingest_returnsNilBelowMinimumBeatsPerWindow() {
        var analyzer = HRVAnalyzer()
        // Default minimum is 30 beats.
        let reading = analyzer.ingest(intervals: intervals(count: 10), quality: .good, artefactRate: 0)
        XCTAssertNil(reading)
    }

    func test_ingest_returnsNilAboveMaximumArtefactRate() {
        var analyzer = HRVAnalyzer()
        // Default ceiling is 0.25.
        let reading = analyzer.ingest(intervals: intervals(count: 30), quality: .good, artefactRate: 0.5)
        XCTAssertNil(reading)
    }

    func test_ingest_producesAReadingOnceThresholdsAreMet() {
        var analyzer = HRVAnalyzer()
        let reading = analyzer.ingest(intervals: intervals(count: 30), quality: .good, artefactRate: 0)
        XCTAssertNotNil(reading)
        XCTAssertEqual(reading?.measurement.beatCount, 30)
        XCTAssertEqual(reading?.measurement.rmssd ?? -1, 50.0, accuracy: 0.0001)
        XCTAssertEqual(reading?.quality, .good)
    }

    func test_ingest_windowIsBoundedByWindowBeats() {
        var analyzer = HRVAnalyzer()
        // Default window is 60 beats; two 40-beat batches should leave
        // the window capped rather than holding all 80.
        _ = analyzer.ingest(intervals: intervals(count: 40), quality: .good, artefactRate: 0)
        let reading = analyzer.ingest(
            intervals: intervals(count: 40).map {
                BeatInterval(milliseconds: $0.milliseconds, timestamp: $0.timestamp.addingTimeInterval(100))
            },
            quality: .good,
            artefactRate: 0
        )
        XCTAssertEqual(reading?.measurement.beatCount, 60)
    }

    // MARK: - Band before enough history

    func test_ingest_reportsEstablishingBandBeforeEnoughHistory() {
        var analyzer = HRVAnalyzer()
        let reading = analyzer.ingest(intervals: intervals(count: 30), quality: .good, artefactRate: 0)
        XCTAssertEqual(reading?.band, .establishing)
        XCTAssertNil(reading?.personalBaseline)
    }

    // MARK: - Personal baseline and banding

    func test_personalBaseline_becomesAvailableAfterEnoughMeasurements() {
        var analyzer = HRVAnalyzer()
        // Default requires 20 measurements. The first ingest establishes
        // a 30-beat window; each subsequent call adds one more beat while
        // preserving the alternating pattern, so rmssd stays exactly 50
        // for every one of the 20 resulting measurements.
        _ = analyzer.ingest(intervals: intervals(count: 30), quality: .good, artefactRate: 0)
        var lastReading: HRVReading?
        for i in 30..<49 {
            let nextBeat = BeatInterval(
                milliseconds: i.isMultiple(of: 2) ? 800 : 850,
                timestamp: base.addingTimeInterval(Double(i))
            )
            lastReading = analyzer.ingest(intervals: [nextBeat], quality: .good, artefactRate: 0)
        }

        XCTAssertEqual(analyzer.personalBaseline ?? -1, 50.0, accuracy: 0.0001)
        XCTAssertEqual(lastReading?.band, .aroundUsual)
        XCTAssertEqual(lastReading?.personalBaseline ?? -1, 50.0, accuracy: 0.0001)
    }

    // MARK: - Reset and seeding

    func test_reset_clearsWindowButPreservesHistory() {
        var analyzer = HRVAnalyzer()
        analyzer.seedHistory((0..<20).map {
            HRVMeasurement(timestamp: base.addingTimeInterval(Double($0)), rmssd: 42, sdnn: 10, meanBPM: 70, beatCount: 30, artefactRate: 0)
        })
        XCTAssertEqual(analyzer.personalBaseline ?? -1, 42, accuracy: 0.0001)

        analyzer.reset()

        // History (and therefore the baseline) survives a reset — only
        // the in-progress window is cleared, so a fresh window still
        // needs to rebuild from scratch before producing a reading.
        XCTAssertEqual(analyzer.personalBaseline ?? -1, 42, accuracy: 0.0001)
        XCTAssertNil(analyzer.ingest(intervals: intervals(count: 5), quality: .good, artefactRate: 0))
    }

    func test_seedHistory_populatesRecentHistory() {
        var analyzer = HRVAnalyzer()
        let seeded = (0..<5).map {
            HRVMeasurement(timestamp: base.addingTimeInterval(Double($0)), rmssd: Double($0), sdnn: 10, meanBPM: 70, beatCount: 30, artefactRate: 0)
        }
        analyzer.seedHistory(seeded)
        XCTAssertEqual(analyzer.recentHistory.count, 5)
    }

    // MARK: - Correlation with stress

    func test_correlateWithStress_returnsNilWithFewerThan15Pairs() {
        let measurements = (0..<10).map {
            HRVMeasurement(timestamp: base.addingTimeInterval(Double($0)), rmssd: Double($0), sdnn: 10, meanBPM: 70, beatCount: 30, artefactRate: 0)
        }
        let result = HRVAnalyzer.correlateWithStress(measurements: measurements) { _ in 0.5 }
        XCTAssertNil(result)
    }

    func test_correlateWithStress_skipsMeasurementsWithNoStressData() {
        // 20 measurements, but stress data only available for every
        // other one — 10 valid pairs isn't enough to clear the minimum.
        let measurements = (0..<20).map {
            HRVMeasurement(timestamp: base.addingTimeInterval(Double($0)), rmssd: Double($0), sdnn: 10, meanBPM: 70, beatCount: 30, artefactRate: 0)
        }
        let result = HRVAnalyzer.correlateWithStress(measurements: measurements) { timestamp in
            let index = Int(timestamp.timeIntervalSince(base))
            return index.isMultiple(of: 2) ? 0.5 : nil
        }
        XCTAssertNil(result)
    }

    func test_correlateWithStress_computesCorrelationAcrossAvailablePairs() {
        let measurements = (1...15).map {
            HRVMeasurement(timestamp: base.addingTimeInterval(Double($0)), rmssd: Double($0) * 10, sdnn: 10, meanBPM: 70, beatCount: 30, artefactRate: 0)
        }
        // Perfectly inverse relationship between rmssd and stress.
        let result = HRVAnalyzer.correlateWithStress(measurements: measurements) { timestamp in
            let index = timestamp.timeIntervalSince(base)
            return -index
        }
        XCTAssertEqual(result ?? 0, -1.0, accuracy: 0.0001)
    }
}
