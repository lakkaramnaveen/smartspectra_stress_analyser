import AVFoundation

/// Generates a single, gentle, continuously-evolving tone whose pitch
/// tracks stress and whose loudness breathes in time with the person's
/// own detected breathing rate.
///
/// This is genuinely the first feature in this app that produces sound
/// — nothing else here plays audio. It's off by default; see the
/// consent note in `BiofeedbackArtView` for why that default matters
/// more than it might first appear.
///
/// No `AVAudioSession` configuration anywhere in this file —
/// deliberately. Audio session *categories* are an iOS concept; macOS
/// apps talk to `AVAudioEngine` directly with no session setup required.
///
/// ## Why the render block reads plain properties, not actor state
///
/// `AVAudioSourceNode`'s render block runs on Core Audio's real-time
/// thread — a context with hard constraints (no allocation, no locks,
/// no blocking) that Swift's actor isolation model isn't built for.
/// This class stays `@MainActor` for its public API, but the render
/// block itself reads three plain `Double` fields directly, marked
/// `nonisolated(unsafe)`, rather than hopping through the actor. A torn
/// read of a `Double` mid-update is, at worst, one audio buffer using a
/// stale-but-valid value for a few milliseconds — inaudible, never a
/// crash or memory corruption. This is the accepted trade-off for
/// real-time audio code; there's no way to satisfy strict actor
/// isolation inside an audio callback and still have it be real-time
/// safe.
@MainActor
final class AmbientToneEngine {

    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private(set) var isRunning = false

    private let sampleRate: Double

    // Written from the main actor via the update methods below, read
    // directly from the render block — see the type doc comment.
    private nonisolated(unsafe) var targetFrequencyHz: Double = 220
    private nonisolated(unsafe) var breathCycleHz: Double = 0.2  // ~12 breaths/min, a reasonable resting default
    private nonisolated(unsafe) var targetAmplitude: Double = 0

    // Pure DSP state — only ever touched from inside the render block
    // itself, never from the main actor.
    private nonisolated(unsafe) var phase: Double = 0
    private nonisolated(unsafe) var breathPhase: Double = 0

    init() {
        sampleRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
    }

    func start() throws {
        guard !isRunning else { return }

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!

        let node = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList in
            guard let self else { return noErr }

            let frequency = self.targetFrequencyHz
            let breathHz = self.breathCycleHz
            let amplitude = self.targetAmplitude
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)

            for frame in 0..<Int(frameCount) {
                // The one part of this sound that's genuine biofeedback
                // rather than a decorative mapping: loudness rises and
                // falls on the person's actual breathing rate, not an
                // arbitrary LFO.
                let breathEnvelope = (sin(self.breathPhase) + 1) / 2
                let sample = Float(sin(self.phase) * amplitude * (0.6 + 0.4 * breathEnvelope))

                for buffer in buffers {
                    let bufferPointer = UnsafeMutableBufferPointer<Float>(buffer)
                    if frame < bufferPointer.count {
                        bufferPointer[frame] = sample
                    }
                }

                self.phase += 2 * .pi * frequency / self.sampleRate
                if self.phase > 2 * .pi { self.phase -= 2 * .pi }
                self.breathPhase += 2 * .pi * breathHz / self.sampleRate
                if self.breathPhase > 2 * .pi { self.breathPhase -= 2 * .pi }
            }

            return noErr
        }

        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        sourceNode = node

        engine.prepare()
        try engine.start()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        engine.stop()
        if let sourceNode {
            engine.detach(sourceNode)
        }
        sourceNode = nil
        isRunning = false
    }

    /// Narrow, calm register — roughly A3 to E4 — mapped smoothly rather
    /// than jumping, and never reaching a register that could read as
    /// alarm-like.
    func updateStress(_ score: Double) {
        let clamped = min(max(score, 0), 1)
        targetFrequencyHz = 220 + (clamped * 110)
    }

    func updateBreathingRate(_ breathsPerMinute: Double) {
        guard breathsPerMinute > 0 else { return }
        breathCycleHz = breathsPerMinute / 60
    }

    /// Deliberately quiet even at "full" volume — this is meant to sit
    /// under attention, not demand it.
    func setVolume(_ volume: Double) {
        targetAmplitude = min(max(volume, 0), 1) * 0.25
    }
}
