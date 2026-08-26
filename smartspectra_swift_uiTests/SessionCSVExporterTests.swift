import XCTest
@testable import smartspectra_swift_ui

final class SessionCSVExporterTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)
    private let header = "timestamp,stress_score,heart_rate,breathing_rate,eda,emotional_state,gaze_confidence"

    private func snapshot(
        offsetSeconds: TimeInterval,
        stressScore: Double = 0.5,
        heartRate: Double = 72.0,
        breathingRate: Double = 14.0,
        eda: Double = 0.025,
        emotionalState: String = "calm",
        gazeConfidence: Double = 0.95
    ) -> SessionSnapshot {
        SessionSnapshot(
            timestamp: base.addingTimeInterval(offsetSeconds),
            stressScore: stressScore,
            heartRate: heartRate,
            breathingRate: breathingRate,
            eda: eda,
            emotionalState: emotionalState,
            gazeConfidence: gazeConfidence
        )
    }

    func test_csv_forEmptyRecording_isJustTheHeader() {
        let recording = SessionRecording(difficulty: "medium", snapshots: [])
        XCTAssertEqual(SessionCSVExporter.csv(for: recording), header)
    }

    func test_csv_formatsOneRowWithExpectedFieldWidths() {
        let snap = snapshot(offsetSeconds: 0)
        let recording = SessionRecording(difficulty: "medium", snapshots: [snap])

        let formatter = ISO8601DateFormatter()
        let expectedRow = [
            formatter.string(from: snap.timestamp),
            "0.5000",
            "72.0",
            "14.0",
            "0.0250",
            "calm",
            "0.95"
        ].joined(separator: ",")

        XCTAssertEqual(SessionCSVExporter.csv(for: recording), "\(header)\n\(expectedRow)")
    }

    func test_csv_sortsRowsByTimestampRegardlessOfInputOrder() {
        let later = snapshot(offsetSeconds: 20, stressScore: 0.9)
        let earlier = snapshot(offsetSeconds: 0, stressScore: 0.1)
        let middle = snapshot(offsetSeconds: 10, stressScore: 0.5)

        // Deliberately out of order.
        let recording = SessionRecording(difficulty: "medium", snapshots: [later, earlier, middle])
        let lines = SessionCSVExporter.csv(for: recording).components(separatedBy: "\n")

        XCTAssertEqual(lines.count, 4) // header + 3 rows
        XCTAssertTrue(lines[1].hasPrefix(ISO8601DateFormatter().string(from: earlier.timestamp)))
        XCTAssertTrue(lines[2].hasPrefix(ISO8601DateFormatter().string(from: middle.timestamp)))
        XCTAssertTrue(lines[3].hasPrefix(ISO8601DateFormatter().string(from: later.timestamp)))
    }

    func test_csv_includesOneRowPerSnapshot() {
        let recording = SessionRecording(
            difficulty: "medium",
            snapshots: (0..<5).map { snapshot(offsetSeconds: TimeInterval($0)) }
        )
        let lines = SessionCSVExporter.csv(for: recording).components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 6) // header + 5 rows
    }

    func test_csv_preservesEmotionalStateStringVerbatim() {
        let recording = SessionRecording(
            difficulty: "medium",
            snapshots: [snapshot(offsetSeconds: 0, emotionalState: "anxious")]
        )
        XCTAssertTrue(SessionCSVExporter.csv(for: recording).contains("anxious"))
    }
}
