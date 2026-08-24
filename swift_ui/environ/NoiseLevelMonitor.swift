import AVFoundation

/// Measures ambient noise level via a live microphone tap.
///
/// ## What this is
///
/// A single number, computed roughly once a second: the root-mean-square
/// amplitude of whatever the microphone is picking up, scaled into a
/// rough 0...1 "level" — the same underlying idea as a VU meter.
///
/// ## What this is not
///
/// Nothing is ever recorded, transcribed, stored, or transmitted.
/// `installTap` gives raw sample buffers; this reduces each buffer to
/// one number and discards the audio immediately — there's no code path
/// here that could retain, save, or send actual sound, because the
/// audio samples themselves are never kept past the RMS calculation.
///
/// ## Why this needs a new permission
///
/// Unlike `AppUsageMonitor`'s `NSWorkspace` calls, microphone access is
/// TCC-gated: it requires an `NSMicrophoneUsageDescription` entry in
/// this target's Info settings (a one-time Xcode project change, not a
/// Swift file) and triggers a real system permission prompt the first
/// time this runs. This is the most privacy-sensitive capability in the
/// app, and `EnvironmentCoordinator` treats it that way — off by
/// default, gated behind its own explicit toggle.
final class NoiseLevelMonitor {

    /// Fired with a normalized level, roughly once a second — throttled
    /// here rather than firing on every audio buffer (which arrives
    /// dozens of times a second and would be far too frequent for
    /// anything downstream to use meaningfully).
    var onLevelSample: ((Double) -> Void)?

    private var audioEngine: AVAudioEngine?
    private var lastEmittedAt: Date = .distantPast
    private let minimumEmitInterval: TimeInterval = 1.0

    func start() {
        stop()

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)

        // The tap closure runs on a real-time audio thread. Real-time
        // audio callbacks must stay fast and avoid anything that could
        // block (locks, allocation, actor hops) — an RMS pass over a
        // buffer this size is cheap enough to do directly here. Only the
        // lightweight "notify someone" step hops over to the main actor,
        // via the callback the coordinator provides.
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self, let channelData = buffer.floatChannelData?[0] else { return }

            let frameCount = Int(buffer.frameLength)
            guard frameCount > 0 else { return }

            var sumSquares: Float = 0
            for index in 0..<frameCount {
                let sample = channelData[index]
                sumSquares += sample * sample
            }
            let rms = sqrt(sumSquares / Float(frameCount))

            // Heuristic scaling into 0...1 for a typical ambient/speech
            // range — not a calibrated decibel meter, and not presented
            // as one anywhere in the UI.
            let normalized = min(Double(rms) * 8, 1.0)

            self.emit(normalized)
        }

        do {
            try engine.start()
            audioEngine = engine
        } catch {
            print("NoiseLevelMonitor: failed to start — \(error.localizedDescription)")
        }
    }

    func stop() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
    }

    private func emit(_ level: Double) {
        let now = Date()
        guard now.timeIntervalSince(lastEmittedAt) >= minimumEmitInterval else { return }
        lastEmittedAt = now

        Task { @MainActor [weak self] in
            self?.onLevelSample?(level)
        }
    }
}
