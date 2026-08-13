import Foundation

/// Recovers inter-beat intervals from a photoplethysmography waveform.
///
/// Pure and UI-free, testable against synthetic waveforms.
///
/// ## Why this is harder than it looks
///
/// A camera samples at roughly 30 fps, giving one sample every ~33 ms.
/// RMSSD in healthy adults sits somewhere around 20–90 ms, so raw
/// frame-indexed peak timing has quantisation error of the same order as
/// the quantity being measured — the resulting "variability" would be
/// mostly an artefact of the frame clock.
///
/// Two mitigations, both applied below:
///
///  1. **Parabolic interpolation.** Fitting a parabola through the peak
///     sample and its two neighbours recovers the true peak position to
///     a fraction of a sample. This is the standard fix and typically
///     cuts timing error several-fold.
///  2. **Artefact rejection.** Missed beats produce doubled intervals and
///     spurious peaks produce halved ones. Either admitted into the
///     series inflates RMSSD enormously, so intervals implausible in
///     absolute terms *or* relative to their neighbours are dropped and
///     counted.
///
/// Even with both, camera-derived intervals remain substantially noisier
/// than a chest strap. That constraint is why the output is only ever
/// compared against the user's own history — see `HRVBand`.
struct BeatDetector {

    let config: HRVConfig

    // MARK: - State

    private var buffer: [Double] = []
    private var bufferStart: Date?
    private var lastPeakTime: Date?
    private var estimatedSampleRate: Double = 0

    /// Rolling count for the artefact rate reported with each window.
    private(set) var acceptedCount = 0
    private(set) var rejectedCount = 0

    init(config: HRVConfig = .default) {
        self.config = config
    }

    // MARK: - Result

    struct Result: Equatable {
        let intervals: [BeatInterval]
        let quality: BeatSignalQuality
        let sampleRateHz: Double
    }

    // MARK: - Ingestion

    /// Feed a batch of waveform samples.
    ///
    /// - Parameters:
    ///   - samples: raw PPG amplitude values.
    ///   - batchTimestamp: when the batch was captured.
    ///   - batchDuration: elapsed time this batch covers, used to
    ///     estimate the sample rate. Pass `nil` on the first batch.
    mutating func ingest(
        samples: [Double],
        batchTimestamp: Date,
        batchDuration: TimeInterval?
    ) -> Result {
        guard !samples.isEmpty else {
            return Result(intervals: [], quality: .unusable, sampleRateHz: estimatedSampleRate)
        }

        if let batchDuration, batchDuration > 0 {
            let observed = Double(samples.count) / batchDuration
            // Smooth the estimate — batch boundaries jitter.
            estimatedSampleRate = estimatedSampleRate == 0
                ? observed
                : (estimatedSampleRate * 0.8) + (observed * 0.2)
        }

        // Below the floor, peak timing is too coarse to mean anything.
        // Returning `.unusable` rather than a plausible-looking number is
        // the whole point of having a floor.
        guard estimatedSampleRate >= config.minimumSampleRateHz else {
            return Result(intervals: [], quality: .unusable, sampleRateHz: estimatedSampleRate)
        }

        if bufferStart == nil { bufferStart = batchTimestamp }
        buffer.append(contentsOf: samples)

        // Keep roughly 10 seconds of waveform — enough for several beats
        // with margin for the detrending window.
        let maxSamples = Int(estimatedSampleRate * 10)
        if buffer.count > maxSamples {
            let dropped = buffer.count - maxSamples
            buffer.removeFirst(dropped)
            bufferStart = bufferStart?.addingTimeInterval(Double(dropped) / estimatedSampleRate)
        }

        let intervals = detectIntervals()
        return Result(
            intervals: intervals,
            quality: currentQuality(),
            sampleRateHz: estimatedSampleRate
        )
    }

    mutating func reset() {
        buffer.removeAll()
        bufferStart = nil
        lastPeakTime = nil
        acceptedCount = 0
        rejectedCount = 0
    }

    var artefactRate: Double {
        let total = acceptedCount + rejectedCount
        return total > 0 ? Double(rejectedCount) / Double(total) : 0
    }

    // MARK: - Detection

    private mutating func detectIntervals() -> [BeatInterval] {
        guard let bufferStart, estimatedSampleRate > 0 else { return [] }

        let detrended = detrend(buffer)
        guard detrended.count > 5 else { return [] }

        // Adaptive threshold: 60% of the window's peak amplitude. A fixed
        // threshold fails as soon as lighting or distance changes the
        // signal's scale, which happens constantly with a webcam.
        let maxAmplitude = detrended.max() ?? 0
        guard maxAmplitude > 0 else { return [] }
        let threshold = maxAmplitude * 0.6

        // Refractory period: no two beats closer than 300 ms (200 bpm).
        let refractorySamples = Int(estimatedSampleRate * 0.3)

        var peakIndices: [Double] = []
        var index = 1

        while index < detrended.count - 1 {
            let value = detrended[index]

            let isLocalMax = value > detrended[index - 1] && value >= detrended[index + 1]
            guard isLocalMax, value >= threshold else {
                index += 1
                continue
            }

            // Sub-sample peak position — the mitigation described in the
            // type comment. Without this, every interval is a multiple of
            // the frame period and the resulting RMSSD is largely a
            // measure of the camera's frame clock.
            let refined = parabolicPeak(
                previous: detrended[index - 1],
                current: value,
                next: detrended[index + 1]
            )
            peakIndices.append(Double(index) + refined)

            index += max(refractorySamples, 1)
        }

        return intervals(from: peakIndices, bufferStart: bufferStart)
    }

    private mutating func intervals(
        from peakIndices: [Double],
        bufferStart: Date
    ) -> [BeatInterval] {
        guard peakIndices.count >= 2 else { return [] }

        var results: [BeatInterval] = []
        var previousMs: Double?

        for pair in zip(peakIndices, peakIndices.dropFirst()) {
            let deltaSamples = pair.1 - pair.0
            let deltaMs = (deltaSamples / estimatedSampleRate) * 1000

            guard BeatInterval.plausibleRange.contains(deltaMs) else {
                rejectedCount += 1
                continue
            }

            // Relative check: a genuine beat-to-beat change of more than
            // ~30% is almost always a detection error rather than
            // physiology. This is the standard guard against the doubled
            // and halved intervals a missed or spurious peak produces.
            if let previousMs {
                let relativeChange = abs(deltaMs - previousMs) / previousMs
                if relativeChange > 0.30 {
                    rejectedCount += 1
                    continue
                }
            }

            let peakTime = bufferStart.addingTimeInterval(pair.1 / estimatedSampleRate)
            results.append(BeatInterval(milliseconds: deltaMs, timestamp: peakTime))
            previousMs = deltaMs
            acceptedCount += 1
        }

        return results
    }

    // MARK: - Helpers

    /// Remove slow drift (breathing, lighting changes, head movement) so
    /// the adaptive threshold tracks pulse amplitude rather than baseline
    /// wander.
    private func detrend(_ samples: [Double]) -> [Double] {
        let window = max(Int(estimatedSampleRate * 0.75), 3)
        guard samples.count > window else { return samples }

        var output: [Double] = []
        output.reserveCapacity(samples.count)

        for index in samples.indices {
            let lower = max(0, index - window / 2)
            let upper = min(samples.count, index + window / 2)
            let localMean = samples[lower..<upper].reduce(0, +) / Double(upper - lower)
            output.append(samples[index] - localMean)
        }

        return output
    }

    /// Offset of the true peak relative to the sampled maximum, in
    /// fractional samples, via three-point parabolic fit.
    private func parabolicPeak(previous: Double, current: Double, next: Double) -> Double {
        let denominator = previous - (2 * current) + next
        guard abs(denominator) > 1e-9 else { return 0 }
        let offset = 0.5 * (previous - next) / denominator
        // A fit implying the peak is more than half a sample away means
        // the parabola didn't fit; fall back to the sampled position.
        return abs(offset) <= 0.5 ? offset : 0
    }

    private func currentQuality() -> BeatSignalQuality {
        guard estimatedSampleRate >= config.minimumSampleRateHz else { return .unusable }

        switch artefactRate {
        case ..<0.10: return .good
        case ..<config.maximumArtefactRate: return .marginal
        default: return .unusable
        }
    }
}
