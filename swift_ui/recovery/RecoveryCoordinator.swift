import Foundation
import SwiftUI

/// Owns recovery detection and decides when the panel is worth showing.
///
/// The gating here is most of the value. A recovery panel that appears
/// the instant a breathing overlay closes — which is exactly when
/// readings start dropping — turns one intervention into two, at the
/// moment the user is trying to get back to what they were doing.
@MainActor
final class RecoveryCoordinator: ObservableObject {

    /// Current recovery state, when a panel should be visible.
    @Published private(set) var state: RecoveryState?

    /// Set briefly when an episode resolves, so the panel can show the
    /// settled message before dismissing itself.
    @Published private(set) var hasSettled = false

    private var detector: RecoveryDetector
    private let config: RecoveryConfig

    private var lastPanelShownAt: Date?
    private var interventionEndedAt: Date?
    private var dismissTask: Task<Void, Never>?
    private var userDismissedEpisode = false

    init(config: RecoveryConfig = .default) {
        self.config = config
        self.detector = RecoveryDetector(config: config)
    }

    // MARK: - Baseline

    /// Seed the baseline from session history.
    ///
    /// Called by `AppModel` after `SessionStoring` has been read, so a
    /// returning user gets a meaningful "usual range" from their first
    /// spike rather than waiting for this session to accumulate enough
    /// calm samples.
    func seedBaseline(from recordings: [SessionRecording]) {
        let calmScores = recordings
            .flatMap(\.snapshots)
            .map(\.stressScore)
            .filter { $0 < config.peakThreshold }

        guard calmScores.count >= 60 else {
            detector.setHistoricalBaseline(nil)
            return
        }

        let sorted = calmScores.sorted()
        detector.setHistoricalBaseline(
            StressBaseline(
                value: sorted[sorted.count / 2],
                sampleCount: sorted.count,
                source: .history
            )
        )
    }

    var baseline: StressBaseline { detector.baseline }

    // MARK: - Lifecycle

    func startSession() {
        detector.reset()
        state = nil
        hasSettled = false
        lastPanelShownAt = nil
        interventionEndedAt = nil
        userDismissedEpisode = false
    }

    func endSession() {
        dismissTask?.cancel()
        state = nil
        hasSettled = false
    }

    /// Called when a breathing intervention finishes, starting the quiet
    /// period before recovery may surface.
    func noteInterventionEnded() {
        interventionEndedAt = Date()
    }

    // MARK: - Ingestion

    /// Feed a stress score. No-ops harmlessly when nothing is happening.
    func ingest(score: Double, suppressed: Bool) {
        let outcome = detector.ingest(score: score)

        switch outcome {
        case .idle:
            break

        case .recovering(let recoveryState):
            guard shouldSurface(suppressed: suppressed) else {
                // Keep tracking silently — if the user later leaves the
                // suppressing context mid-descent, the panel can still
                // appear with accurate state rather than starting over.
                return
            }
            present(recoveryState)

        case .settled(let recoveryState):
            // Only show the settled message if the panel was already up.
            // A user who never saw the descent doesn't need to be told
            // it finished — that's an interruption announcing a
            // non-event.
            guard state != nil else {
                userDismissedEpisode = false
                return
            }
            state = recoveryState
            hasSettled = true
            scheduleAutoDismiss()
        }
    }

    // MARK: - User actions

    /// Dismiss for this episode. Won't reappear until the next distinct
    /// peak — a panel the user closed reopening thirty seconds later is
    /// how a helpful feature becomes an annoying one.
    func dismiss() {
        dismissTask?.cancel()
        state = nil
        hasSettled = false
        userDismissedEpisode = true
        detector.endEpisode()
    }

    // MARK: - Private

    private func shouldSurface(suppressed: Bool) -> Bool {
        // Already visible — updates flow through without re-gating.
        if state != nil { return true }

        if userDismissedEpisode { return false }
        if suppressed { return false }

        // Quiet period after a breathing session. Readings drop sharply
        // right after one ends, which is precisely when this would
        // otherwise fire.
        if let interventionEndedAt,
           Date().timeIntervalSince(interventionEndedAt) < config.postInterventionQuietPeriod {
            return false
        }

        if let lastPanelShownAt,
           Date().timeIntervalSince(lastPanelShownAt) < config.cooldown {
            return false
        }

        return true
    }

    private func present(_ recoveryState: RecoveryState) {
        if state == nil {
            lastPanelShownAt = Date()
        }
        state = recoveryState
        hasSettled = false
    }

    private func scheduleAutoDismiss() {
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(config.settledDismissDelay))
            guard !Task.isCancelled else { return }
            self.state = nil
            self.hasSettled = false
            self.userDismissedEpisode = false
        }
    }
}
