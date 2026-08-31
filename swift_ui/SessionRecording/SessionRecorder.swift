import Foundation
import os

private let logger = Logger(subsystem: "com.presagetech.smartspectra-swift-ui", category: "SessionRecorder")

/// Records a live session as a series of throttled snapshots, then hands
/// the finished recording to a `SessionStoring` implementation.
///
/// Deliberately separate from `AppModel` — same pattern as
/// `StressScoringEngine` and `BiometricEngine` elsewhere in this
/// codebase: a single-purpose, independently testable unit that
/// `AppModel` composes rather than absorbs. `AppModel` only ever calls
/// three methods: `start`, `capture`, `stop`.
@MainActor
final class SessionRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var capturedSnapshotCount = 0

    private let store: SessionStoring
    private let samplingInterval: TimeInterval

    private var recording: SessionRecording?
    private var lastCaptureAt: Date?

    /// - Parameters:
    ///   - store: Where finished recordings are persisted.
    ///   - samplingInterval: Minimum time between captured snapshots.
    ///     Defaults to 1s — frequent enough for a meaningful stress
    ///     curve, sparse enough that an hour-long session is still a
    ///     small JSON file (~3600 snapshots).
    init(store: SessionStoring = FileSessionStore(), samplingInterval: TimeInterval = 1.0) {
        self.store = store
        self.samplingInterval = samplingInterval
    }

    /// Begin a new recording. Any prior in-progress recording that wasn't
    /// explicitly stopped is discarded — callers own the start/stop
    /// pairing (e.g. `AppModel.start()` / `AppModel.stop()`).
    func start(difficulty: String) {
        recording = SessionRecording(difficulty: difficulty)
        lastCaptureAt = nil
        capturedSnapshotCount = 0
        isRecording = true
    }

    /// Capture a snapshot if enough time has passed since the last one.
    ///
    /// Safe to call on *every* metrics update (e.g. from a delegate
    /// callback that fires many times per second) — throttling happens
    /// internally, so callers don't need to manage their own timers.
    func capture(
        stressScore: Double,
        heartRate: Double,
        breathingRate: Double,
        eda: Double,
        emotionalState: String,
        gazeConfidence: Double
    ) {
        guard isRecording, recording != nil else { return }

        let now = Date()
        if let lastCaptureAt, now.timeIntervalSince(lastCaptureAt) < samplingInterval {
            return
        }
        lastCaptureAt = now

        let snapshot = SessionSnapshot(
            timestamp: now,
            stressScore: stressScore,
            heartRate: heartRate,
            breathingRate: breathingRate,
            eda: eda,
            emotionalState: emotionalState,
            gazeConfidence: gazeConfidence
        )

        recording?.snapshots.append(snapshot)
        capturedSnapshotCount = recording?.snapshots.count ?? 0
    }

    /// Finish the recording and persist it. Returns the saved recording
    /// so the caller can, for example, immediately show a summary screen.
    @discardableResult
    func stop() -> SessionRecording? {
        guard var finished = recording else {
            isRecording = false
            return nil
        }

        finished.endedAt = Date()
        isRecording = false
        recording = nil
        lastCaptureAt = nil

        do {
            try store.save(finished)
        } catch {
            // The recording is still returned even if persistence fails,
            // so an in-memory summary can still be shown for this run —
            // it just won't survive an app relaunch. Surfacing this as a
            // thrown error to AppModel would turn a "nice to have"
            // feature into something that can break the main start/stop
            // flow, which isn't the right tradeoff here.
            logger.error("Failed to save recording: \(error.localizedDescription, privacy: .public)")
        }

        return finished
    }

    /// Discard the current recording without saving it (e.g. session
    /// errored out before producing any meaningful data).
    func cancel() {
        recording = nil
        lastCaptureAt = nil
        isRecording = false
        capturedSnapshotCount = 0
    }
}
