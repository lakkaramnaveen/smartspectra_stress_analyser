import Foundation

/// Detects the arc from a stress peak back toward the user's baseline.
///
/// Pure and UI-free — same shape as `StressScoringEngine` and
/// `GazePostureAnalyzer`, testable with plain input/output assertions.
///
/// The core problem this solves is **noise**. Stress scores wobble
/// several points between consecutive samples, so a naive
/// "score went down" check fires constantly at any elevated level. A
/// real descent has to clear a meaningful gap from the peak *and* hold
/// direction across several samples before it counts.
struct RecoveryDetector {

    let config: RecoveryConfig

    // MARK: - Episode state

    private var peakScore: Double?
    private var peakAt: Date?
    private var descendingRun: Int = 0
    private var lastScore: Double?
    private var isTracking = false

    // MARK: - Baseline estimation

    /// Calm samples observed this session, used to estimate baseline.
    private var calmSamples: [Double] = []

    /// Baseline supplied from session history, if available.
    private var historicalBaseline: StressBaseline?

    init(config: RecoveryConfig = .default) {
        self.config = config
    }

    // MARK: - Result

    enum Outcome: Equatable {
        /// Nothing notable.
        case idle
        /// A confirmed descent from a peak is underway.
        case recovering(RecoveryState)
        /// The episode has resolved back to baseline.
        case settled(RecoveryState)
    }

    // MARK: - Baseline

    /// Provide a baseline computed from past sessions. Takes precedence
    /// over the in-session estimate once confident, since a full history
    /// is a better estimate of "usual" than one session's calm patches.
    mutating func setHistoricalBaseline(_ baseline: StressBaseline?) {
        historicalBaseline = baseline
    }

    var baseline: StressBaseline {
        if let historicalBaseline, historicalBaseline.isConfident {
            return historicalBaseline
        }

        guard calmSamples.count >= 30 else {
            return historicalBaseline ?? .assumedDefault
        }

        // Median rather than mean: a session containing one long spike
        // shouldn't drag the estimate of "usual" upward.
        let sorted = calmSamples.sorted()
        return StressBaseline(
            value: sorted[sorted.count / 2],
            sampleCount: sorted.count,
            source: .currentSession
        )
    }

    // MARK: - Ingestion

    mutating func ingest(score: Double, now: Date = Date()) -> Outcome {
        defer { lastScore = score }

        let baselineValue = baseline.value

        // Collect calm readings for baseline estimation. Only readings
        // below the peak threshold contribute — including spike samples
        // would let a stressful session inflate its own idea of normal.
        if score < config.peakThreshold {
            calmSamples.append(score)
            if calmSamples.count > 600 { calmSamples.removeFirst() }
        }

        // --- Peak tracking -------------------------------------------------

        if score >= config.peakThreshold {
            if peakScore == nil || score > (peakScore ?? 0) {
                peakScore = score
                peakAt = now
            }
            // Any climb resets descent confirmation: an episode that's
            // still rising isn't a recovery.
            descendingRun = 0
            return isTracking ? .idle : .idle
        }

        guard let peak = peakScore, let peakTime = peakAt else {
            return .idle
        }

        // --- Descent confirmation ------------------------------------------

        if let last = lastScore, score < last {
            descendingRun += 1
        } else if let last = lastScore, score > last + 0.02 {
            // Small upward wobble is tolerated; a real climb isn't.
            descendingRun = 0
        }

        let clearedGap = (peak - score) >= config.descentDelta
        let confirmed = descendingRun >= config.confirmationSamples

        guard clearedGap, confirmed || isTracking else {
            return .idle
        }

        isTracking = true

        // --- Phase ----------------------------------------------------------

        let span = max(peak - baselineValue, 0.001)
        let remaining = max(score - baselineValue, 0)
        let progress = min(max(1 - (remaining / span), 0), 1)

        let phase: RecoveryPhase
        if remaining <= config.settledTolerance {
            phase = .settled
        } else if (remaining / span) <= config.settlingFraction {
            phase = .settling
        } else {
            phase = .easing
        }

        let state = RecoveryState(
            phase: phase,
            peakScore: peak,
            currentScore: score,
            baseline: baselineValue,
            progress: progress,
            peakAt: peakTime
        )

        if phase == .settled {
            endEpisode()
            return .settled(state)
        }

        return .recovering(state)
    }

    /// Clear episode state without clearing the baseline estimate —
    /// baseline knowledge is session-long and shouldn't be thrown away
    /// each time an episode resolves.
    mutating func endEpisode() {
        peakScore = nil
        peakAt = nil
        descendingRun = 0
        isTracking = false
    }

    mutating func reset() {
        endEpisode()
        calmSamples.removeAll()
        lastScore = nil
    }
}
