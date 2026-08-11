import Foundation
import SwiftUI

/// Wires the trend analyzer, alert policy, and notifier together and
/// publishes the result for SwiftUI.
///
/// `AppModel` composes this the same way it composes `SessionRecorder`:
/// one property, two call sites (`ingest` and `reset`). All the
/// prediction machinery stays behind this facade.
@MainActor
final class StressPredictionCoordinator: ObservableObject {

    /// Latest forecast — drives the always-visible trend indicator.
    @Published private(set) var forecast: StressForecast = .empty

    /// The most recent alert, if one is currently worth showing in-app.
    /// Set to `nil` when the user dismisses it.
    @Published var activeAlert: StressAlert?

    /// User-facing toggle for system notifications. The in-app banner is
    /// always shown; this only governs whether it also leaves the app.
    @Published var notificationsEnabled = true

    private var analyzer: StressTrendAnalyzer
    private var policy: InterventionAlertPolicy
    private let notifier: StressNotifying

    init(
        analyzer: StressTrendAnalyzer = StressTrendAnalyzer(),
        policy: InterventionAlertPolicy = InterventionAlertPolicy(),
        notifier: StressNotifying? = nil
    ) {
        self.analyzer = analyzer
        self.policy = policy
        // Constructed in the body rather than as a default argument:
        // default-argument expressions evaluate non-isolated, which trips
        // actor-isolation checking for MainActor-bound types.
        self.notifier = notifier ?? SystemStressNotifier()
    }

    /// Feed a new stress score. Safe to call on every update — the
    /// analyzer's rolling window and the policy's cooldown handle
    /// throttling internally.
    func ingest(score: Double, interventionActive: Bool) {
        forecast = analyzer.ingest(score: score)

        guard let alert = policy.evaluate(
            forecast,
            interventionAlreadyActive: interventionActive
        ) else {
            return
        }

        activeAlert = alert

        if notificationsEnabled {
            Task { await notifier.deliver(alert) }
        }
    }

    /// Clear all trend state. Called when a session starts, so one
    /// session's tail doesn't bleed into the next one's forecast.
    func reset() {
        analyzer.reset()
        policy.reset()
        forecast = .empty
        activeAlert = nil
    }

    func dismissAlert() {
        activeAlert = nil
    }
}
