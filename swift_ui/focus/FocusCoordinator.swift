import Foundation
import SwiftUI

/// Owns focus mode: the phase engine, stress tracking during phases,
/// notification suppression, and the break-suggestion policy.
///
/// `AppModel` composes this and consults `suppressesInterruptions` before
/// showing predictive alerts.
@MainActor
final class FocusCoordinator: ObservableObject {

    @Published private(set) var engine = FocusSessionEngine()
    @Published var configuration: FocusConfiguration = .pomodoro

    /// Summary awaiting acknowledgement, shown after each phase ends.
    @Published var pendingSummary: FocusSummary?

    /// Set when sustained distress crosses the early-exit bar. An
    /// *offer*, not an automatic action — the user decides.
    @Published var earlyExitOffered = false

    /// Completed focus blocks today, for the tab's at-a-glance count.
    @Published private(set) var focusBlocksToday = 0

    private var samples: [FocusStressSample] = []
    private var sustainedHighStressStart: Date?
    private var longestSustainedHighStress: TimeInterval = 0
    private var lastCountedDay: Date?

    // MARK: - Interruption policy

    /// Whether interruptions should be held back right now.
    ///
    /// Consulted by `AppModel` before surfacing a predictive stress
    /// alert. True only during an active, unpaused *focus* phase —
    /// breaks are exactly when a deferred nudge should land.
    var suppressesInterruptions: Bool {
        engine.isRunning && !engine.isPaused && engine.phase == .focus
    }

    var isActive: Bool { engine.isRunning }

    // MARK: - Thresholds

    /// Stress at or above this counts toward sustained-distress timing.
    private let highStressThreshold: Double = 0.80

    /// How long distress must persist unbroken before an early exit is
    /// offered.
    ///
    /// Set high on purpose. Deep work legitimately elevates stress
    /// markers — that's engagement, not suffering — so a low bar here
    /// would interrupt good work to report a false positive. Four
    /// unbroken minutes at 80%+ is no longer plausibly productive
    /// engagement.
    private let sustainedDistressThreshold: TimeInterval = 240

    // MARK: - Lifecycle

    init() {
        engine.onPhaseEnded = { [weak self] phase, duration, completedFully in
            self?.handlePhaseEnded(phase, duration: duration, completedFully: completedFully)
        }
    }

    func start() {
        resetPhaseTracking()
        earlyExitOffered = false
        engine.start(configuration: configuration)
    }

    func stop() {
        engine.stop()
    }

    func pause() { engine.pause() }
    func resume() { engine.resume() }
    func skip() { engine.skipToNextPhase() }

    func dismissSummary() {
        pendingSummary = nil
    }

    func declineEarlyExit() {
        earlyExitOffered = false
        // Reset the window so declining doesn't re-prompt seconds later.
        sustainedHighStressStart = Date()
    }

    // MARK: - Stress ingestion

    /// Feed a stress score. Called from `AppModel` on every derived-state
    /// update; no-ops when focus mode isn't running.
    func ingest(stressScore: Double) {
        guard engine.isRunning, !engine.isPaused else { return }

        let now = Date()
        samples.append(FocusStressSample(timestamp: now, score: stressScore))

        // Only focus phases count toward distress tracking — elevated
        // stress during a break is a signal about the preceding block,
        // not grounds for cutting the break short.
        guard engine.phase == .focus else {
            sustainedHighStressStart = nil
            return
        }

        if stressScore >= highStressThreshold {
            if sustainedHighStressStart == nil {
                sustainedHighStressStart = now
            }
            if let start = sustainedHighStressStart {
                let sustained = now.timeIntervalSince(start)
                longestSustainedHighStress = max(longestSustainedHighStress, sustained)

                if sustained >= sustainedDistressThreshold && !earlyExitOffered {
                    earlyExitOffered = true
                }
            }
        } else {
            sustainedHighStressStart = nil
        }
    }

    // MARK: - Private

    private func handlePhaseEnded(
        _ phase: FocusPhase,
        duration: TimeInterval,
        completedFully: Bool
    ) {
        let phaseSamples = samples.map(\.score)

        let summary = FocusSummary(
            phase: phase,
            plannedDuration: configuration.duration(for: phase),
            actualDuration: duration,
            completedFully: completedFully,
            roundNumber: engine.completedFocusRounds,
            averageStress: phaseSamples.isEmpty ? nil : phaseSamples.average,
            peakStress: phaseSamples.max(),
            sustainedHighStressSeconds: longestSustainedHighStress
        )

        if phase == .focus && completedFully {
            incrementDailyCount()
        }

        pendingSummary = summary
        earlyExitOffered = false
        resetPhaseTracking()
    }

    private func resetPhaseTracking() {
        samples.removeAll()
        sustainedHighStressStart = nil
        longestSustainedHighStress = 0
    }

    private func incrementDailyCount() {
        let today = Calendar.current.startOfDay(for: Date())
        if lastCountedDay != today {
            focusBlocksToday = 0
            lastCountedDay = today
        }
        focusBlocksToday += 1
    }
}
