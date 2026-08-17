import Foundation
import SwiftUI

/// Owns app-usage tracking and the stress-association analysis drawn
/// from it.
///
/// Two deliberate scope limits, both privacy-driven:
///
/// **Off by default.** Every other data source in this app is something
/// the person is already actively generating by using Composure — a
/// biometric session they started, a note they wrote, a night they
/// logged. This is different: a timestamped record of *every other app*
/// they use is arguably more revealing about their whole digital life
/// than the biometric data itself, and defaulting it to on would mean
/// silently starting that record before anyone chose to.
///
/// **Monitoring only runs inside an active Composure session.**
/// `startMonitoring()`/`stopMonitoring()` are called from
/// `AppModel.start()`/`stop()`, not on app launch. There's no path in
/// this coordinator where app-focus tracking runs in the background
/// while Composure itself isn't actively being used.
@MainActor
final class AppUsageCoordinator: ObservableObject {

    @Published private(set) var isEnabled: Bool
    @Published private(set) var isMonitoringActive = false
    @Published private(set) var associations: [AppStressAssociation] = []
    @Published private(set) var isAnalyzing = false
    @Published private(set) var totalTrackedMinutes: Double = 0

    private let store: AppUsageStoring
    private let sessionStore: SessionStoring
    private let analyzer: AppStressAnalyzer
    private let monitor = AppUsageMonitor()

    private var sessions: [AppFocusSession]

    /// Sessions older than this are dropped every time the log is
    /// saved. An indefinitely growing, timestamped record of app usage
    /// is exactly the kind of data that becomes a liability the longer
    /// it's kept, so this prunes itself rather than relying on anyone
    /// to remember to clear it.
    private let retentionDays = 30

    init(
        store: AppUsageStoring? = nil,
        sessionStore: SessionStoring,
        analyzer: AppStressAnalyzer = AppStressAnalyzer()
    ) {
        let resolved = store ?? FileAppUsageStore()
        self.store = resolved
        self.sessionStore = sessionStore
        self.analyzer = analyzer

        let state = resolved.load()
        self.isEnabled = state.isEnabled
        self.sessions = state.sessions
        self.totalTrackedMinutes = state.sessions.reduce(0) { $0 + $1.duration / 60 }

        monitor.onSessionCompleted = { [weak self] session in
            self?.record(session)
        }
    }

    // MARK: - Preference

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        persist()
        if !enabled { stopMonitoring() }
    }

    /// Erases the log outright — a distinct, explicit action from simply
    /// disabling tracking, the same separation `ProfileCoordinator` keeps
    /// between removing a profile and deleting its data. Turning
    /// tracking off stops collecting; this is the only thing that erases
    /// what's already been collected.
    func clearHistory() {
        sessions.removeAll()
        associations = []
        totalTrackedMinutes = 0
        persist()
    }

    // MARK: - Lifecycle

    func startMonitoring() {
        guard isEnabled, !isMonitoringActive else { return }
        monitor.start()
        isMonitoringActive = true
    }

    func stopMonitoring() {
        guard isMonitoringActive else { return }
        monitor.stop()
        isMonitoringActive = false
        Task { await refresh() }
    }

    // MARK: - Analysis

    func refresh() async {
        isAnalyzing = true
        defer { isAnalyzing = false }

        let recordings = sessionStore.loadSummaries().compactMap { try? sessionStore.load(id: $0.id) }
        let stressSamples: [(timestamp: Date, stressScore: Double)] = recordings.flatMap { recording in
            recording.snapshots.map { (timestamp: $0.timestamp, stressScore: $0.stressScore) }
        }
        let currentSessions = sessions
        let analyzer = self.analyzer

        associations = await Task.detached(priority: .utility) {
            analyzer.associate(appSessions: currentSessions, stressSamples: stressSamples)
        }.value
    }

    // MARK: - Private

    private func record(_ session: AppFocusSession) {
        sessions.append(session)
        totalTrackedMinutes += session.duration / 60
        persist()
    }

    private func persist() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) ?? .distantPast
        sessions.removeAll { $0.end < cutoff }

        do {
            try store.save(AppUsageState(sessions: sessions, isEnabled: isEnabled))
        } catch {
            print("AppUsageCoordinator: failed to persist — \(error.localizedDescription)")
        }
    }
}
