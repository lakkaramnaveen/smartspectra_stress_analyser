import Foundation

// MARK: - Configuration

/// Tunables for trend analysis, pulled out of the analyzer for the same
/// reason `StressScoringConfig` is separate from `StressScoringEngine`:
/// so QA/demo builds can loosen thresholds without touching the math.
struct StressTrendConfig {
    /// How many samples to keep. At ~1 sample/sec this is a 2-minute
    /// window — long enough to smooth out momentary noise, short enough
    /// that the slope reflects "right now" rather than the whole session.
    var windowCapacity: Int = 120

    /// Minimum samples before any trend is reported. Below this the fit
    /// is meaningless and the analyzer returns `.insufficientData`
    /// rather than a confident-looking number derived from three points.
    var minimumSamples: Int = 20

    /// Slope magnitude (stress-units/second) below which movement is
    /// treated as noise and reported as `.steady`. 0.0005/s ≈ 3% per
    /// minute — under that, it's drift, not a trend.
    var steadySlopeThreshold: Double = 0.0005

    /// Minimum R² before `timeToThreshold` is extrapolated at all. A
    /// noisy scatter can still produce a steep best-fit line; refusing
    /// to extrapolate below this is what stops the UI showing confident
    /// ETAs derived from nothing.
    var minimumConfidenceForETA: Double = 0.35

    /// Don't project further ahead than this. A 40-minute ETA is
    /// arithmetically valid and practically meaningless.
    var maximumForecastHorizon: TimeInterval = 15 * 60

    /// The score the forecast extrapolates toward. Should match
    /// `StressScoringConfig.extremeStressThreshold` so the prediction and
    /// the actual intervention agree on what "critical" means.
    var interventionThreshold: Double = 0.95

    static let `default` = StressTrendConfig()
}

// MARK: - Timed Sample

/// A stress score paired with when it was observed. Timestamps matter
/// because samples don't arrive on a perfectly even cadence — the SDK
/// delivers metrics irregularly, so regressing against sample *index*
/// instead of elapsed time would distort the slope whenever the feed
/// stutters.
struct TimedStressSample: Equatable {
    let value: Double
    let timestamp: Date
}

// MARK: - Analyzer

/// Fits a least-squares line through recent stress samples to determine
/// direction, rate of change, and time-to-threshold.
///
/// Pure and UI-free by design — same rationale as `StressScoringEngine`.
/// No SwiftUI, no Combine, no SDK types, so it can be unit tested with
/// plain input/output assertions.
struct StressTrendAnalyzer {
    let config: StressTrendConfig

    private var samples: RollingBuffer<TimedStressSample>

    init(config: StressTrendConfig = .default) {
        self.config = config
        self.samples = RollingBuffer<TimedStressSample>(capacity: config.windowCapacity)
    }

    /// Record a new observation and return the updated forecast.
    mutating func ingest(score: Double, at timestamp: Date = Date()) -> StressForecast {
        samples.append(TimedStressSample(value: score, timestamp: timestamp))
        return forecast()
    }

    /// Recompute the forecast from the current window without adding a
    /// sample. Useful for refreshing UI on a timer.
    func forecast() -> StressForecast {
        let window = samples.elements

        guard window.count >= config.minimumSamples,
              let first = window.first,
              let latest = window.last else {
            return StressForecast(
                currentScore: samples.elements.last?.value ?? 0,
                direction: .insufficientData,
                slopePerSecond: 0,
                confidence: 0,
                timeToThreshold: nil,
                sampleCount: window.count
            )
        }

        // Regress against seconds-elapsed rather than sample index, so an
        // irregular sample cadence doesn't warp the slope.
        let xs = window.map { $0.timestamp.timeIntervalSince(first.timestamp) }
        let ys = window.map(\.value)

        let fit = LinearFit(xs: xs, ys: ys)

        guard let fit else {
            return StressForecast(
                currentScore: latest.value,
                direction: .insufficientData,
                slopePerSecond: 0,
                confidence: 0,
                timeToThreshold: nil,
                sampleCount: window.count
            )
        }

        let direction = classify(slope: fit.slope)
        let eta = estimateTimeToThreshold(
            currentScore: latest.value,
            slope: fit.slope,
            confidence: fit.rSquared
        )

        return StressForecast(
            currentScore: latest.value,
            direction: direction,
            slopePerSecond: fit.slope,
            confidence: fit.rSquared,
            timeToThreshold: eta,
            sampleCount: window.count
        )
    }

    mutating func reset() {
        samples.removeAll()
    }

    // MARK: - Private

    private func classify(slope: Double) -> StressTrendDirection {
        if abs(slope) < config.steadySlopeThreshold { return .steady }
        return slope > 0 ? .rising : .falling
    }

    private func estimateTimeToThreshold(
        currentScore: Double,
        slope: Double,
        confidence: Double
    ) -> TimeInterval? {
        // Only extrapolate when climbing, when the fit is trustworthy,
        // and when we're not already at/over the threshold.
        guard slope > config.steadySlopeThreshold,
              confidence >= config.minimumConfidenceForETA,
              currentScore < config.interventionThreshold else {
            return nil
        }

        let remaining = config.interventionThreshold - currentScore
        let seconds = remaining / slope

        guard seconds > 0, seconds <= config.maximumForecastHorizon else { return nil }
        return seconds
    }
}

// MARK: - Least-Squares Fit

/// Ordinary least-squares fit of `y = slope·x + intercept`, plus the R²
/// goodness-of-fit that tells callers whether the slope means anything.
///
/// Kept as its own type rather than inlined into the analyzer so the
/// numerical work can be tested against known inputs independently of
/// any stress-domain semantics.
struct LinearFit {
    let slope: Double
    let intercept: Double
    let rSquared: Double

    /// Returns `nil` when a fit is undefined — fewer than two points, or
    /// all x-values identical (a vertical line has no finite slope).
    init?(xs: [Double], ys: [Double]) {
        guard xs.count == ys.count, xs.count >= 2 else { return nil }

        let n = Double(xs.count)
        let meanX = xs.reduce(0, +) / n
        let meanY = ys.reduce(0, +) / n

        var covariance = 0.0   // Σ (x - x̄)(y - ȳ)
        var varianceX = 0.0    // Σ (x - x̄)²

        for (x, y) in zip(xs, ys) {
            let dx = x - meanX
            covariance += dx * (y - meanY)
            varianceX += dx * dx
        }

        guard varianceX > 0 else { return nil }

        let slope = covariance / varianceX
        let intercept = meanY - slope * meanX

        // R² = 1 - (residual sum of squares / total sum of squares)
        var residualSS = 0.0
        var totalSS = 0.0
        for (x, y) in zip(xs, ys) {
            let predicted = slope * x + intercept
            residualSS += (y - predicted) * (y - predicted)
            totalSS += (y - meanY) * (y - meanY)
        }

        // A perfectly flat series has zero total variance; the line fits
        // it exactly, so treat that as R² = 1 rather than dividing by 0.
        let rSquared = totalSS > 0 ? max(0, 1 - residualSS / totalSS) : 1

        self.slope = slope
        self.intercept = intercept
        self.rSquared = rSquared
    }
}
