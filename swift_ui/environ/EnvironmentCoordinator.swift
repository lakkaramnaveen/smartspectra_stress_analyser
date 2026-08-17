import Foundation
import SwiftUI

/// Owns lighting and noise sampling, and the correlation drawn from
/// them once a session ends.
///
/// The two dimensions are treated very differently, deliberately:
///
/// - **Lighting** analyzes camera frames the app is already capturing
///   for its core purpose. Nothing new is observed, so it needs no
///   toggle and runs automatically alongside a session.
/// - **Noise** requires a new sensor and a new system permission. It's
///   off by default, gated behind `noiseMonitoringEnabled`, and — like
///   `AppUsageCoordinator` — only ever active during a running
///   Composure session, never in the background.
@MainActor
final class EnvironmentCoordinator: ObservableObject {

    @Published private(set) var noiseMonitoringEnabled: Bool
    @Published private(set) var isNoiseMonitoringActive = false
    @Published private(set) var currentBrightness: Double?
    @Published private(set) var currentNoiseLevel: Double?
    @Published private(set) var associations: [EnvironmentAssociation] = []
    @Published private(set) var isAnalysing = false

    private let store: EnvironmentStoring
    private let sessionStore: SessionStoring
    private let lightingAnalyzer = LightingAnalyzer()
    private let noiseMonitor = NoiseLevelMonitor()
    private let stressAnalyzer = EnvironmentStressAnalyzer()

    private var brightnessSamples: [BrightnessSample]
    private var noiseSamples: [NoiseSample]

    private var lastBrightnessAt: Date = .distantPast
    private let brightnessSampleInterval: TimeInterval = 3

    private let retentionDays = 30

    init(store: EnvironmentStoring? = nil, sessionStore: SessionStoring) {
        let resolved = store ?? FileEnvironmentStore()
        self.store = resolved
        self.sessionStore = sessionStore

        let state = resolved.load()
        self.noiseMonitoringEnabled = state.noiseMonitoringEnabled
        self.brightnessSamples = state.brightnessSamples
        self.noiseSamples = state.noiseSamples

        noiseMonitor.onLevelSample = { [weak self] level in
            self?.recordNoise(level)
        }
    }

    // MARK: - Preference

    func setNoiseMonitoringEnabled(_ enabled: Bool) {
        noiseMonitoringEnabled = enabled
        persist()
        if !enabled { stopNoiseMonitoring() }
    }

    func clearHistory() {
        brightnessSamples.removeAll()
        noiseSamples.removeAll()
        associations = []
        currentBrightness = nil
        currentNoiseLevel = nil
        persist()
    }

    // MARK: - Lighting (no toggle — see type doc comment)

    /// Called from `AppModel`'s existing frame-received delegate
    /// callback. Throttled internally so this runs a handful of times a
    /// minute, not on every camera frame.
    func ingestFrame(_ image: NSImage) {
        let now = Date()
        guard now.timeIntervalSince(lastBrightnessAt) >= brightnessSampleInterval else { return }
        lastBrightnessAt = now

        guard let brightness = lightingAnalyzer.brightness(of: image) else { return }
        currentBrightness = brightness
        brightnessSamples.append(BrightnessSample(timestamp: now, value: brightness))
    }

    // MARK: - Noise

    func startNoiseMonitoring() {
        guard noiseMonitoringEnabled, !isNoiseMonitoringActive else { return }
        noiseMonitor.start()
        isNoiseMonitoringActive = true
    }

    func stopNoiseMonitoring() {
        guard isNoiseMonitoringActive else { return }
        noiseMonitor.stop()
        isNoiseMonitoringActive = false
    }

    private func recordNoise(_ level: Double) {
        currentNoiseLevel = level
        noiseSamples.append(NoiseSample(timestamp: Date(), value: level))
    }

    // MARK: - Session lifecycle

    func startSession() {
        startNoiseMonitoring()
    }

    func endSession() {
        stopNoiseMonitoring()
        persist()
        Task { await refresh() }
    }

    // MARK: - Analysis

    func refresh() async {
        isAnalysing = true
        defer { isAnalysing = false }

        let recordings = sessionStore.loadSummaries().compactMap { try? sessionStore.load(id: $0.id) }
        let stressSamples: [(timestamp: Date, stressScore: Double)] = recordings.flatMap { recording in
            recording.snapshots.map { (timestamp: $0.timestamp, stressScore: $0.stressScore) }
        }
        let brightness = brightnessSamples.map { (timestamp: $0.timestamp, value: $0.value) }
        let noise = noiseSamples.map { (timestamp: $0.timestamp, value: $0.value) }
        let analyzer = stressAnalyzer

        associations = await Task.detached(priority: .utility) { () -> [EnvironmentAssociation] in
            var results: [EnvironmentAssociation] = []
            if let lighting = analyzer.associate(dimension: .lighting, readings: brightness, stressSamples: stressSamples) {
                results.append(lighting)
            }
            if let noiseResult = analyzer.associate(dimension: .noise, readings: noise, stressSamples: stressSamples) {
                results.append(noiseResult)
            }
            return results
        }.value
    }

    // MARK: - Private

    private func persist() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) ?? .distantPast
        brightnessSamples.removeAll { $0.timestamp < cutoff }
        noiseSamples.removeAll { $0.timestamp < cutoff }

        let state = EnvironmentState(
            brightnessSamples: brightnessSamples,
            noiseSamples: noiseSamples,
            noiseMonitoringEnabled: noiseMonitoringEnabled
        )
        do {
            try store.save(state)
        } catch {
            print("EnvironmentCoordinator: failed to persist — \(error.localizedDescription)")
        }
    }
}
