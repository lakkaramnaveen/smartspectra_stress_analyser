import Foundation

// MARK: - Alert

/// A decision to surface something to the user, with copy already chosen.
struct StressAlert: Identifiable, Equatable {
    enum Kind: Equatable {
        /// Stress is climbing toward the threshold.
        case risingTrend(etaSeconds: TimeInterval?)
        /// Stress has come down meaningfully from a peak.
        case recovered
    }

    let id = UUID()
    let kind: Kind
    let title: String
    let body: String
    let raisedAt: Date

    static func == (lhs: StressAlert, rhs: StressAlert) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Policy Configuration

struct AlertPolicyConfig {
    /// Minimum gap between two rising-trend alerts. Without this, a user
    /// hovering near the trigger point gets pinged every few seconds —
    /// which is both useless and, for a stress app specifically,
    /// actively counterproductive.
    var cooldown: TimeInterval = 5 * 60

    /// Only warn when the projected crossing is within this horizon.
    /// Further out than this and the nudge has no urgency to act on.
    var alertHorizon: TimeInterval = 4 * 60

    /// Don't warn below this stress level, however steep the slope. A
    /// climb from 0.05 to 0.15 is technically "rising fast" and entirely
    /// unremarkable.
    var minimumScoreToWarn: Double = 0.45

    /// Required fit quality before a warning fires.
    var minimumConfidence: Double = 0.4

    /// Fire a recovery note when stress drops this far below the peak
    /// that triggered a warning.
    var recoveryDelta: Double = 0.25

    static let `default` = AlertPolicyConfig()
}

// MARK: - Policy

/// Decides *whether* a forecast deserves the user's attention.
///
/// Deliberately separate from both the analyzer (which only does math)
/// and the notification service (which only does delivery). Keeping the
/// "should we interrupt someone right now" judgement in its own type
/// means the rules are testable in isolation and easy to tune without
/// touching either neighbour.
struct InterventionAlertPolicy {
    let config: AlertPolicyConfig

    private var lastAlertAt: Date?
    private var peakSinceLastAlert: Double = 0
    private var awaitingRecovery = false

    init(config: AlertPolicyConfig = .default) {
        self.config = config
    }

    /// Evaluate a forecast. Returns an alert if one should be raised now,
    /// `nil` otherwise.
    mutating func evaluate(
        _ forecast: StressForecast,
        now: Date = Date(),
        interventionAlreadyActive: Bool
    ) -> StressAlert? {
        // Never stack a predictive nudge on top of an active breathing
        // intervention — the user is already being helped.
        guard !interventionAlreadyActive else { return nil }

        if awaitingRecovery {
            peakSinceLastAlert = max(peakSinceLastAlert, forecast.currentScore)
            if forecast.currentScore <= peakSinceLastAlert - config.recoveryDelta {
                awaitingRecovery = false
                return StressAlert(
                    kind: .recovered,
                    title: "You're coming back down",
                    body: "Stress has eased noticeably from its peak. Nice work.",
                    raisedAt: now
                )
            }
        }

        guard shouldWarn(forecast, now: now) else { return nil }

        lastAlertAt = now
        peakSinceLastAlert = forecast.currentScore
        awaitingRecovery = true

        let etaText = forecast.formattedTimeToThreshold
        let body = etaText.map {
            "On the current trend you'd reach your threshold in \($0). A short breathing break now would help."
        } ?? "Stress has been climbing steadily. A short breathing break now would help."

        return StressAlert(
            kind: .risingTrend(etaSeconds: forecast.timeToThreshold),
            title: "Stress is climbing",
            body: body,
            raisedAt: now
        )
    }

    mutating func reset() {
        lastAlertAt = nil
        peakSinceLastAlert = 0
        awaitingRecovery = false
    }

    // MARK: - Private

    private func shouldWarn(_ forecast: StressForecast, now: Date) -> Bool {
        guard forecast.direction == .rising,
              forecast.currentScore >= config.minimumScoreToWarn,
              forecast.confidence >= config.minimumConfidence,
              let eta = forecast.timeToThreshold,
              eta <= config.alertHorizon else {
            return false
        }

        if let lastAlertAt, now.timeIntervalSince(lastAlertAt) < config.cooldown {
            return false
        }

        return true
    }
}
