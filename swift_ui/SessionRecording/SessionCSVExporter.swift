import Foundation
import os
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif

private let logger = Logger(subsystem: "com.presagetech.smartspectra-swift-ui", category: "SessionCSVExporter")

/// Converts a `SessionRecording` into CSV and, on macOS, offers a native
/// save panel so the user picks where it goes.
enum SessionCSVExporter {
    /// Builds CSV text. Pulled apart from the save-panel logic below so
    /// it can be unit tested without touching AppKit or the filesystem.
    static func csv(for recording: SessionRecording) -> String {
        var lines = [
            "timestamp,stress_score,heart_rate,breathing_rate,eda,emotional_state,gaze_confidence"
        ]

        let formatter = ISO8601DateFormatter()
        let sorted = recording.snapshots.sorted { $0.timestamp < $1.timestamp }

        for snapshot in sorted {
            let row = [
                formatter.string(from: snapshot.timestamp),
                String(format: "%.4f", snapshot.stressScore),
                String(format: "%.1f", snapshot.heartRate),
                String(format: "%.1f", snapshot.breathingRate),
                String(format: "%.4f", snapshot.eda),
                snapshot.emotionalState,
                String(format: "%.2f", snapshot.gazeConfidence)
            ].joined(separator: ",")
            lines.append(row)
        }

        return lines.joined(separator: "\n")
    }

    #if os(macOS)
    /// Presents a save panel and writes the CSV if the user confirms.
    @MainActor
    static func exportWithSavePanel(_ recording: SessionRecording) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "composure-session-\(shortID(recording.id)).csv"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let csv = csv(for: recording)
            do {
                try csv.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                logger.error("Failed to write CSV: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private static func shortID(_ id: UUID) -> String {
        String(id.uuidString.prefix(8))
    }
    #endif
}
