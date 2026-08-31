import Foundation

/// Tunable thresholds for stress/emotion scoring. Pulled out of the
/// calculator so they can be swapped per build config (e.g. lower
/// thresholds for QA/demo builds) without touching logic.
struct StressScoringConfig {
    var edaStressThreshold: Double = 0.08
    var erraticBreathingThreshold: Double = 22.0 // breaths per minute
    var pulseNormalizationCeiling: Double = 120.0 // bpm
    var edaNormalizationCeiling: Double = 0.1
    var breathingNormalizationCeiling: Double = 25.0

    /// Stress score (0...1) above which we consider the user in genuine
    /// distress and worth interrupting with a breathing intervention.
    /// Deliberately high — this is a last-resort nudge, not a notification
    /// for every minor fluctuation. Tuned up from an earlier 0.80 default
    /// after user feedback that it fired too often during normal work.
    var extremeStressThreshold: Double = 0.95

    static let `default` = StressScoringConfig()

    /// Rescales the fixed defaults around a user's own resting baseline
    /// instead of using the same absolute thresholds for everyone.
    ///
    /// Multipliers below are a starting point, not a clinically validated
    /// model — how far above *this person's own* resting reading counts
    /// as "maximally stressed." Each is floored at half the population
    /// default so an unusually low resting reading (e.g. EDA near zero)
    /// can't collapse a threshold to near-zero and make the factor
    /// saturate to 1.0 permanently.
    static func personalized(from baseline: StressBaseline, fallback: StressScoringConfig = .default) -> StressScoringConfig {
        var config = fallback

        config.edaStressThreshold = max(baseline.edaRestingMean * 1.6, fallback.edaStressThreshold * 0.5)
        config.erraticBreathingThreshold = max(baseline.breathingRestingMean * 1.5, fallback.erraticBreathingThreshold * 0.5)
        config.edaNormalizationCeiling = max(baseline.edaRestingMean * 2.0, fallback.edaNormalizationCeiling * 0.5)
        config.breathingNormalizationCeiling = max(baseline.breathingRestingMean * 1.8, fallback.breathingNormalizationCeiling * 0.5)

        // Pulse wasn't reliably sampled in every calibration run (face
        // tracking can drop briefly) — only override the population
        // default if calibration actually captured a usable reading.
        if baseline.pulseRestingMean > 0 {
            config.pulseNormalizationCeiling = max(baseline.pulseRestingMean * 1.5, fallback.pulseNormalizationCeiling * 0.5)
        }

        return config
    }
}

/// Stateless calculator that turns raw vitals into a stress score and an
/// emotional-state classification.
///
/// Pulled out of `AppModel` deliberately: this is pure math with zero
/// dependency on SwiftUI, Combine, or the SDK, which means it can be unit
/// tested with plain input/output assertions and reused (e.g. server-side
/// analytics) without dragging in UI frameworks.
struct StressScoringEngine {
    let config: StressScoringConfig

    init(config: StressScoringConfig = .default) {
        self.config = config
    }

    /// Combined stress score derived from EDA and breathing rate.
    /// Returns nil if there isn't enough signal yet (e.g. breathing rate
    /// hasn't been observed) — callers should treat nil as "no update."
    func stressScore(eda: Double, breathingRPM: Double) -> Double? {
        guard breathingRPM > 0 else { return nil }

        let edaFactor = min(abs(eda) / config.edaStressThreshold, 1.0)
        let breathFactor = min(breathingRPM / config.erraticBreathingThreshold, 1.0)
        return (edaFactor + breathFactor) / 2.0
    }

    /// Emotional state classification independent of the stress score —
    /// factors in pulse as well, since elevated heart rate with calm
    /// breathing reads differently than the inverse.
    func emotionalState(pulseBPM: Double, eda: Double, breathingRPM: Double) -> (state: EmotionalState, intensity: Double) {
        let pulseNormalized = min(pulseBPM / config.pulseNormalizationCeiling, 1.0)
        let edaNormalized = min(abs(eda) / config.edaNormalizationCeiling, 1.0)
        let breathingNormalized = min(breathingRPM / config.breathingNormalizationCeiling, 1.0)

        let intensity = (pulseNormalized + edaNormalized + breathingNormalized) / 3.0

        let state: EmotionalState
        switch intensity {
        case ..<0.3: state = .calm
        case ..<0.5: state = .focused
        case ..<0.7: state = .anxious
        default: state = .stressed
        }

        return (state, intensity)
    }

    func shouldTriggerIntervention(forStressScore score: Double) -> Bool {
        score > config.extremeStressThreshold
    }
}
