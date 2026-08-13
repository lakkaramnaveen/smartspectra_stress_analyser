import Foundation
import SwiftUI
import AVFoundation

/// Runs a meditation: advances cues against elapsed time, optionally
/// plays narration, and collects stress samples for the summary.
///
/// Like `FocusSessionEngine`, timing is **deadline-based**: elapsed time
/// is derived from a stored start `Date` rather than accumulated by a
/// ticking counter, so an irregular run loop can't cause cue drift over
/// a ten-minute sitting.
@MainActor
final class MeditationSessionEngine: ObservableObject {

    @Published private(set) var meditation: Meditation?
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var currentCue: MeditationCue?
    @Published private(set) var isRunning = false
    @Published private(set) var isPaused = false

    /// Fires when the meditation finishes or is ended early.
    var onEnded: ((Meditation, _ elapsed: TimeInterval, _ completedFully: Bool, _ samples: [Double]) -> Void)?

    private var startedAt: Date?
    private var pausedElapsed: TimeInterval?
    private var tickTask: Task<Void, Never>?
    private var stressSamples: [Double] = []
    private var audioPlayer: AVAudioPlayer?

    var progress: Double {
        guard let meditation, meditation.duration > 0 else { return 0 }
        return min(elapsed / meditation.duration, 1)
    }

    var remaining: TimeInterval {
        guard let meditation else { return 0 }
        return max(0, meditation.duration - elapsed)
    }

    // MARK: - Control

    func start(_ meditation: Meditation) {
        stopInternal()

        self.meditation = meditation
        stressSamples = []
        elapsed = 0
        currentCue = meditation.cue(at: 0)
        startedAt = Date()
        pausedElapsed = nil
        isRunning = true
        isPaused = false

        startAudioIfAvailable(for: meditation)
        startTicking()
    }

    func pause() {
        guard isRunning, !isPaused, let startedAt else { return }
        pausedElapsed = Date().timeIntervalSince(startedAt)
        isPaused = true
        tickTask?.cancel()
        audioPlayer?.pause()
    }

    func resume() {
        guard isPaused, let paused = pausedElapsed else { return }
        // Rebase the start so elapsed picks up where it left off.
        startedAt = Date().addingTimeInterval(-paused)
        pausedElapsed = nil
        isPaused = false
        audioPlayer?.play()
        startTicking()
    }

    /// End early. Still reports samples — a meditation stopped at seven
    /// minutes produced seven minutes of real data.
    func stop() {
        guard let meditation, isRunning else { return }
        let finalElapsed = elapsed
        let samples = stressSamples

        stopInternal()
        onEnded?(meditation, finalElapsed, false, samples)
    }

    /// Feed a stress reading. Called from `AppModel`; no-ops when idle
    /// or paused.
    func ingest(stressScore: Double) {
        guard isRunning, !isPaused else { return }
        stressSamples.append(stressScore)
    }

    // MARK: - Private

    private func startTicking() {
        tickTask?.cancel()
        // `Task { }` inside a @MainActor type inherits main-actor isolation,
        // so `tick()` is called directly — no `await`, because there's no
        // actor hop to suspend on. Only `Task.sleep` actually suspends here.
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                self?.tick()
            }
        }
    }

    private func tick() {
        guard let meditation, let startedAt, isRunning, !isPaused else { return }

        elapsed = Date().timeIntervalSince(startedAt)
        currentCue = meditation.cue(at: elapsed)

        if elapsed >= meditation.duration {
            let samples = stressSamples
            stopInternal()
            onEnded?(meditation, meditation.duration, true, samples)
        }
    }

    /// Narration is optional and best-effort.
    ///
    /// A missing or unreadable audio file must never prevent the session
    /// running — the cues carry the meditation on their own, so a broken
    /// asset degrades to a silent sitting rather than a dead button.
    private func startAudioIfAvailable(for meditation: Meditation) {
        audioPlayer = nil

        guard let filename = meditation.audioFilename else { return }

        let name = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension

        guard let url = Bundle.main.url(forResource: name, withExtension: ext.isEmpty ? "m4a" : ext) else {
            print("MeditationSessionEngine: audio '\(filename)' not bundled — running silent")
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            player.play()
            audioPlayer = player
        } catch {
            print("MeditationSessionEngine: audio failed to load — \(error.localizedDescription)")
        }
    }

    private func stopInternal() {
        tickTask?.cancel()
        tickTask = nil
        audioPlayer?.stop()
        audioPlayer = nil
        isRunning = false
        isPaused = false
        startedAt = nil
        pausedElapsed = nil
    }
}
