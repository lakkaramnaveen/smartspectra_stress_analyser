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
                csvField(snapshot.emotionalState),
                String(format: "%.2f", snapshot.gazeConfidence)
            ].joined(separator: ",")
            lines.append(row)
        }

        return lines.joined(separator: "\n")
    }

    /// Quotes/escapes a CSV field per RFC 4180 and neutralizes spreadsheet
    /// formula injection (a field starting with `=`, `+`, `-`, or `@` gets
    /// interpreted as a formula by Excel/Numbers/Sheets on open).
    ///
    /// Every field passed through here today is either numeric or a fixed
    /// `EmotionalState` label — none of it is user- or attacker-controlled,
    /// so this is defense-in-depth rather than a fix for a live exploit.
    /// It exists so that if a free-text field (session notes, custom
    /// tags) is ever added to `SessionSnapshot`, it's already routed
    /// through something that won't silently produce a broken or
    /// formula-injectable CSV.
    private static func csvField(_ value: String) -> String {
        var field = value
        if let first = field.unicodeScalars.first, "=+-@".unicodeScalars.contains(first) {
            field = "'" + field
        }
        guard field.contains(where: { ",\"\n\r".contains($0) }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
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
