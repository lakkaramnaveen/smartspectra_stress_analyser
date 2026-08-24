import Foundation

/// Computes variability metrics from a series of beat intervals, and
/// places each result relative to the user's own history.
///
/// Pure and UI-free — same shape as `StressScoringEngine` and
/// `CorrelationAnalyzer`.
struct HRVAnalyzer {

    let config: HRVConfig

    private var window: [BeatInterval] = []
    private var history: [HRVMeasurement] = []

    init(config: HRVConfig = .default) {
        self.config = config
    }

    // MARK: - Metrics

    /// Root mean square of successive differences.
    ///
    /// The standard short-term variability metric, and the one most
    /// reflective of parasympathetic activity. Requires consecutive
    /// intervals — this is exactly why it cannot be computed from
    /// averaged BPM readings, which contain no beat-to-beat structure at
    /// all.
    static func rmssd(_ intervals: [Double]) -> Double? {
        guard intervals.count >= 2 else { return nil }

        let differences = zip(intervals.dropFirst(), intervals).map { $0 - $1 }
        let meanSquare = differences.map { $0 * $0 }.reduce(0, +) / Double(differences.count)
        return meanSquare.squareRoot()
    }

    /// Standard deviation of intervals. Reflects total variability across
    /// the window, including slower rhythms such as breathing, so it
    /// behaves differently from RMSSD and is reported alongside rather
    /// than instead of it.
    static func sdnn(_ intervals: [Double]) -> Double? {
        guard intervals.count >= 2 else { return nil }

        let mean = intervals.reduce(0, +) / Double(intervals.count)
        let variance = intervals
            .map { ($0 - mean) * ($0 - mean) }
            .reduce(0, +) / Double(intervals.count)
        return variance.squareRoot()
    }

    static func meanBPM(_ intervals: [Double]) -> Double? {
        guard !intervals.isEmpty else { return nil }
        let meanMs = intervals.reduce(0, +) / Double(intervals.count)
        guard meanMs > 0 else { return nil }
        return 60000 / meanMs
    }

    // MARK: - Ingestion

    /// Add newly detected intervals and produce a reading if the window
    /// is complete enough to support one.
    mutating func ingest(
        intervals newIntervals: [BeatInterval],
        quality: BeatSignalQuality,
        artefactRate: Double
    ) -> HRVReading? {
        guard quality != .unusable else { return nil }

        window.append(contentsOf: newIntervals)
        if window.count > config.windowBeats {
            window.removeFirst(window.count - config.windowBeats)
        }

        guard window.count >= config.minimumBeatsPerWindow else { return nil }

        // A window rescued only by discarding a quarter of its beats
        // isn't a measurement, it's a guess.
        guard artefactRate <= config.maximumArtefactRate else { return nil }

        let values = window.map(\.milliseconds)

        guard let rmssdValue = Self.rmssd(values),
              let sdnnValue = Self.sdnn(values),
              let bpm = Self.meanBPM(values) else {
            return nil
        }

        let measurement = HRVMeasurement(
            rmssd: rmssdValue,
            sdnn: sdnnValue,
            meanBPM: bpm,
            beatCount: window.count,
            artefactRate: artefactRate
        )

        history.append(measurement)
        if history.count > 500 { history.removeFirst(history.count - 500) }

        return HRVReading(
            measurement: measurement,
            band: band(for: rmssdValue),
            personalBaseline: personalBaseline,
            quality: quality
        )
    }

    mutating func reset() {
        window.removeAll()
    }

    /// Seed history from stored measurements so a returning user gets
    /// personal bands immediately rather than after twenty fresh windows.
    mutating func seedHistory(_ measurements: [HRVMeasurement]) {
        history = Array(measurements.suffix(500))
    }

    var recentHistory: [HRVMeasurement] { history }

    // MARK: - Personal baseline

    /// Median RMSSD across recent measurements.
    ///
    /// Median rather than mean: a handful of noisy windows with inflated
    /// RMSSD would drag a mean upward and make every subsequent genuine
    /// reading look "below usual".
    var personalBaseline: Double? {
        guard history.count >= config.minimumMeasurementsForBaseline else { return nil }
        let sorted = history.map(\.rmssd).sorted()
        return sorted[sorted.count / 2]
    }

    private func band(for value: Double) -> HRVBand {
        guard let baseline = personalBaseline, baseline > 0 else { return .establishing }

        let deviation = ((value - baseline) / baseline) * 100

        if deviation <= -config.bandThresholdPercent { return .belowUsual }
        if deviation >= config.bandThresholdPercent { return .aboveUsual }
        return .aroundUsual
    }

    // MARK: - Correlation with stress

    /// Correlate RMSSD against paired stress scores.
    ///
    /// Reuses `CorrelationAnalyzer` rather than reimplementing Pearson.
    /// The expected sign is negative — lower variability alongside higher
    /// stress — but this reports whatever the user's own data shows,
    /// including nothing.
    static func correlateWithStress(
        measurements: [HRVMeasurement],
        stressAt: (Date) -> Double?
    ) -> Double? {
        var rmssdValues: [Double] = []
        var stressValues: [Double] = []

        for measurement in measurements {
            guard let stress = stressAt(measurement.timestamp) else { continue }
            rmssdValues.append(measurement.rmssd)
            stressValues.append(stress)
        }

        guard rmssdValues.count >= 15 else { return nil }
        return CorrelationAnalyzer.pearson(rmssdValues, stressValues)
    }
}
