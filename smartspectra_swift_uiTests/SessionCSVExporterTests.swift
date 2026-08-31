import XCTest

final class SessionCSVExporterTests: XCTestCase {

    private func recording(emotionalState: String) -> SessionRecording {
        let snapshot = SessionSnapshot(
            timestamp: Date(timeIntervalSince1970: 0),
            stressScore: 0.5,
            heartRate: 70,
            breathingRate: 14,
            eda: 0.02,
            emotionalState: emotionalState,
            gazeConfidence: 0.9
        )
        return SessionRecording(difficulty: "Medium", snapshots: [snapshot])
    }

    func testPlainFieldIsUnquoted() {
        let csv = SessionCSVExporter.csv(for: recording(emotionalState: "Calm"))
        XCTAssertTrue(csv.contains(",Calm,"))
    }

    func testFieldWithCommaIsQuoted() {
        let csv = SessionCSVExporter.csv(for: recording(emotionalState: "Calm, focused"))
        XCTAssertTrue(csv.contains("\"Calm, focused\""))
    }

    func testFieldWithQuoteIsEscaped() {
        let csv = SessionCSVExporter.csv(for: recording(emotionalState: "\"Anxious\""))
        XCTAssertTrue(csv.contains("\"\"\"Anxious\"\"\""))
    }

    func testLeadingEqualsSignIsNeutralized() {
        // A field starting with =, +, -, or @ would otherwise be
        // interpreted as a formula by Excel/Numbers/Sheets on open.
        let csv = SessionCSVExporter.csv(for: recording(emotionalState: "=cmd|'/bin/sh'!A1"))
        XCTAssertFalse(csv.contains(",=cmd"))
        XCTAssertTrue(csv.contains(",'=cmd"))
    }

    func testHeaderRowIsPresent() {
        let csv = SessionCSVExporter.csv(for: recording(emotionalState: "Calm"))
        XCTAssertTrue(csv.hasPrefix("timestamp,stress_score,heart_rate,breathing_rate,eda,emotional_state,gaze_confidence"))
    }
}
