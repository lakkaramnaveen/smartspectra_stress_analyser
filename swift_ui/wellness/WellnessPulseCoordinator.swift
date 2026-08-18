import Foundation
import SwiftUI
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif

/// Computes the current period's coarse stress band from the person's
/// own session history and exports it as a small, identity-free file.
///
/// Read-only against `SessionStoring` — the same on-demand pattern as
/// `FamilyDashboardCoordinator` and `TherapistReportCoordinator`. No
/// network calls, no aggregation, no view of anyone else's data: this
/// coordinator only ever knows about the one profile it belongs to.
/// Anything beyond "here is my own band, as a file I chose to save" is
/// explicitly out of scope — see the note on `WellnessPulseView` for
/// what that leaves out and why.
@MainActor
final class WellnessPulseCoordinator: ObservableObject {

    @Published private(set) var isEnabled: Bool
    @Published private(set) var currentBand: StressBand?
    @Published private(set) var lastExportedAt: Date?

    private let store: WellnessPulseStoring
    private let sessionStore: SessionStoring

    init(store: WellnessPulseStoring? = nil, sessionStore: SessionStoring) {
        let resolved = store ?? FileWellnessPulseStore()
        self.store = resolved
        self.sessionStore = sessionStore
        self.isEnabled = resolved.load().isEnabled
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        try? store.save(WellnessPulseConfig(isEnabled: enabled))
        if enabled { refresh() }
    }

    /// Averages the last 7 days of the person's own sessions into one
    /// band. Recomputed on demand rather than tracked continuously —
    /// this is meant to be checked occasionally, not monitored.
    func refresh() {
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -7, to: Date()) ?? .distantPast

        let recent = sessionStore.loadSummaries().filter { $0.startedAt >= cutoff }
        guard !recent.isEmpty else {
            currentBand = nil
            return
        }

        let average = recent.map(\.averageStress).average
        currentBand = StressBand.classify(average)
    }

    func export() {
        guard let band = currentBand else { return }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let periodLabel = "Week of \(formatter.string(from: Date()))"

        let export = WellnessPulseExport(periodLabel: periodLabel, band: band, generatedAt: Date())
        WellnessPulseExporter.exportWithSavePanel(export) { [weak self] success in
            if success { self?.lastExportedAt = Date() }
        }
    }
}

// MARK: - Preference Store

protocol WellnessPulseStoring {
    func load() -> WellnessPulseConfig
    func save(_ config: WellnessPulseConfig) throws
}

final class FileWellnessPulseStore: WellnessPulseStoring {
    private let fileURL: URL

    init(appSupportSubdirectory: String = "Composure") {
        let fileManager = FileManager.default
        let base = fileManager
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? fileManager.temporaryDirectory
        let directory = base.appendingPathComponent(appSupportSubdirectory, isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("wellness_pulse.json")
    }

    func load() -> WellnessPulseConfig {
        guard let data = try? Data(contentsOf: fileURL),
              let config = try? JSONDecoder().decode(WellnessPulseConfig.self, from: data) else {
            return WellnessPulseConfig()
        }
        return config
    }

    func save(_ config: WellnessPulseConfig) throws {
        let data = try JSONEncoder().encode(config)
        try data.write(to: fileURL, options: .atomic)
    }
}

final class InMemoryWellnessPulseStore: WellnessPulseStoring {
    private var config = WellnessPulseConfig()
    func load() -> WellnessPulseConfig { config }
    func save(_ config: WellnessPulseConfig) throws { self.config = config }
}

// MARK: - Export

enum WellnessPulseExporter {
    #if os(macOS)
    @MainActor
    static func exportWithSavePanel(_ export: WellnessPulseExport, onComplete: @escaping (Bool) -> Void) {
        let text = """
        Wellness Pulse
        Period: \(export.periodLabel)
        Band: \(export.band.label)
        Generated: \(export.generatedAt.formatted(date: .abbreviated, time: .shortened))

        This is a single coarse band (Low, Moderate, or High), self-reported by
        the person who generated it, from a personal wellness app that is not
        a workplace monitoring tool and makes no compliance claim of any kind.
        """

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "wellness-pulse.txt"

        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                onComplete(false)
                return
            }
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
                onComplete(true)
            } catch {
                onComplete(false)
            }
        }
    }
    #endif
}
