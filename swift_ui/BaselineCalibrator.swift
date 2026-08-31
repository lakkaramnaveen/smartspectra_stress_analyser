import Foundation

/// Tunables for a calibration run, pulled out for the same reason
/// `StressTrendConfig` is separate from `StressTrendAnalyzer`.
struct BaselineCalibrationConfig {
    /// How long a calibration run lasts. Long enough to smooth out
    /// momentary noise and let an initial startle at the camera settle,
    /// short enough that a user will actually sit through it.
    var targetDuration: TimeInterval = 60

    /// Minimum samples before a calibration is trusted. Below this the
    /// average is as likely to reflect "face left frame" as "resting
    /// state" — `finish()` refuses to produce a baseline rather than
    /// save a number nobody should trust.
    var minimumSamples: Int = 20

    static let `default` = BaselineCalibrationConfig()
}

/// Accumulates resting vitals during a short "sit still and breathe
/// normally" calibration window and produces a personal `StressBaseline`.
///
/// Pure and UI-free by design — same rationale as `StressTrendAnalyzer`:
/// no SwiftUI, no SDK types, so it can be unit tested with plain
/// input/output assertions and driven from `AppModel` without dragging
/// calibration math into the view layer.
struct BaselineCalibrator {
    let config: BaselineCalibrationConfig

    private(set) var startedAt: Date?
    private var edaSamples: [Double] = []
    private var breathingSamples: [Double] = []
    private var pulseSamples: [Double] = []

    init(config: BaselineCalibrationConfig = .default) {
        self.config = config
    }

    mutating func start(at date: Date = Date()) {
        startedAt = date
        edaSamples.removeAll()
        breathingSamples.removeAll()
        pulseSamples.removeAll()
    }

    /// Record one observation. No-op before `start()` is called, so a
    /// caller can't accidentally accumulate samples outside a run.
    ///
    /// EDA is stored as `abs(eda)` to match how `StressScoringEngine`
    /// consumes it (`abs(eda) / edaStressThreshold`) — the baseline needs
    /// to be in the same units as the value it will later be compared
    /// against.
    mutating func ingest(pulseBPM: Double, eda: Double, breathingRPM: Double) {
        guard startedAt != nil else { return }
        if pulseBPM > 0 { pulseSamples.append(pulseBPM) }
        if breathingRPM > 0 { breathingSamples.append(breathingRPM) }
        edaSamples.append(abs(eda))
    }

    var elapsed: TimeInterval {
        guard let startedAt else { return 0 }
        return Date().timeIntervalSince(startedAt)
    }

    var progress: Double {
        min(elapsed / config.targetDuration, 1.0)
    }

    var isComplete: Bool {
        elapsed >= config.targetDuration
    }

    var hasEnoughSamples: Bool {
        breathingSamples.count >= config.minimumSamples
    }

    /// Finishes calibration and returns the computed baseline, or `nil`
    /// if too few samples were captured to trust the average (e.g. the
    /// user stepped away or the calibration was cancelled early).
    func finish(at date: Date = Date()) -> StressBaseline? {
        guard hasEnoughSamples else { return nil }

        func mean(_ values: [Double]) -> Double {
            values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
        }

        return StressBaseline(
            edaRestingMean: mean(edaSamples),
            breathingRestingMean: mean(breathingSamples),
            pulseRestingMean: mean(pulseSamples),
            sampleCount: breathingSamples.count,
            calibratedAt: date
        )
    }
}
