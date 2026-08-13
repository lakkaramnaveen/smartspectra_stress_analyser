import Foundation
import SwiftUI

// MARK: - Store

protocol ErgonomicsConfigStoring {
    func load() -> ErgonomicsConfig
    func save(_ config: ErgonomicsConfig) throws
}

final class FileErgonomicsConfigStore: ErgonomicsConfigStoring {
    private let fileURL: URL

    init(appSupportSubdirectory: String = "Composure") {
        let fileManager = FileManager.default
        let base = fileManager
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? fileManager.temporaryDirectory

        let directory = base.appendingPathComponent(appSupportSubdirectory, isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        fileURL = directory.appendingPathComponent("ergonomics.json")
    }

    func load() -> ErgonomicsConfig {
        guard let data = try? Data(contentsOf: fileURL),
              let config = try? JSONDecoder().decode(ErgonomicsConfig.self, from: data) else {
            return .default
        }
        return config
    }

    func save(_ config: ErgonomicsConfig) throws {
        let data = try JSONEncoder().encode(config)
        try data.write(to: fileURL, options: .atomic)
    }
}

final class InMemoryErgonomicsConfigStore: ErgonomicsConfigStoring {
    private var config: ErgonomicsConfig

    init(config: ErgonomicsConfig = .default) { self.config = config }
    func load() -> ErgonomicsConfig { config }
    func save(_ config: ErgonomicsConfig) throws { self.config = config }
}

// MARK: - Coordinator

@MainActor
final class ErgonomicsCoordinator: ObservableObject {

    @Published private(set) var stats: ErgonomicsStats = .empty
    @Published var activeNudge: ErgonomicsNudge?
    @Published var config: ErgonomicsConfig {
        didSet { persist() }
    }

    /// Whether a baseline has been established for this session.
    @Published private(set) var hasBaseline = false

    private var analyzer: GazePostureAnalyzer
    private var policy: ErgonomicsNudgePolicy
    private let store: ErgonomicsConfigStoring

    private var sessionStart: Date?
    private var lastBreakAt: Date?
    private var lastSampleAt: Date?
    private var tickTask: Task<Void, Never>?

    /// Set by `AppModel` so nudges don't fire during a focus block,
    /// meditation, or breathing exercise. Reuses the same suppression
    /// concept as the stress alerts rather than inventing a second one.
    var isSuppressed: () -> Bool = { false }

    init(store: ErgonomicsConfigStoring? = nil) {
        let resolved = store ?? FileErgonomicsConfigStore()
        self.store = resolved

        let loaded = resolved.load()
        self.config = loaded
        self.analyzer = GazePostureAnalyzer(config: loaded)
        self.policy = ErgonomicsNudgePolicy(config: loaded)
    }

    // MARK: - Lifecycle

    func startSession() {
        sessionStart = Date()
        lastBreakAt = Date()
        lastSampleAt = nil
        stats = .empty
        analyzer.reset()
        policy.reset()
        hasBaseline = false
        startTicking()
    }

    func endSession() {
        tickTask?.cancel()
        tickTask = nil
        sessionStart = nil
        activeNudge = nil
    }

    // MARK: - Ingestion

    /// Feed a gaze sample. Called from `AppModel`; no-ops when no
    /// session is running.
    func ingest(gaze: GazePoint) {
        guard sessionStart != nil else { return }

        let now = Date()
        let interval = lastSampleAt.map { now.timeIntervalSince($0) } ?? 0
        lastSampleAt = now

        // Guard against a stale gap: if the app was backgrounded or the
        // feed stalled, a single sample shouldn't credit ten minutes of
        // downward gaze in one go.
        let cappedInterval = min(interval, 2.0)

        let reading = analyzer.ingest(
            verticalPosition: gaze.y,
            confidence: gaze.confidence,
            interval: cappedInterval,
            now: now
        )

        hasBaseline = analyzer.baseline != nil

        stats.quality = reading.quality
        stats.driftFromBaseline = reading.drift
        stats.downwardGazeSeconds += reading.downwardIncrement
        stats.longestDownwardStretchSeconds = max(
            stats.longestDownwardStretchSeconds,
            reading.currentDownwardStreak
        )

        evaluateNudges(now: now)
    }

    // MARK: - User actions

    /// User marks a break as taken. Resets the break clock and the
    /// policy's per-kind counters.
    func markBreakTaken() {
        lastBreakAt = Date()
        stats.breaksTaken += 1
        stats.timeSinceBreakSeconds = 0
        policy.breakTaken()
        activeNudge = nil
    }

    /// Re-anchor the vertical baseline to the user's current position.
    func recalibrate() {
        analyzer.recalibrate()
        hasBaseline = false
        stats.driftFromBaseline = nil
    }

    func dismissNudge() {
        activeNudge = nil
    }

    // MARK: - Private

    private func startTicking() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self?.tickClocks()
            }
        }
    }

    /// Screen-time clocks tick independently of gaze samples, so they
    /// keep running when the tracker loses the face. Time spent at the
    /// desk is time at the desk whether or not the camera can see you.
    private func tickClocks() {
        guard let sessionStart else { return }

        let now = Date()
        stats.screenTimeSeconds = now.timeIntervalSince(sessionStart)
        stats.timeSinceBreakSeconds = now.timeIntervalSince(lastBreakAt ?? sessionStart)

        evaluateNudges(now: now)
    }

    private func evaluateNudges(now: Date) {
        guard activeNudge == nil else { return }

        if let nudge = policy.evaluate(
            stats: stats,
            now: now,
            suppressed: isSuppressed()
        ) {
            activeNudge = nudge
        }
    }

    private func persist() {
        // Rebuild both collaborators so a changed threshold takes effect
        // immediately rather than at next launch.
        analyzer = GazePostureAnalyzer(config: config)
        policy = ErgonomicsNudgePolicy(config: config)

        do {
            try store.save(config)
        } catch {
            print("ErgonomicsCoordinator: failed to persist — \(error.localizedDescription)")
        }
    }
}
