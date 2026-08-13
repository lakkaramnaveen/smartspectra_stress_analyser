import Foundation
import SwiftUI

/// Runs the focus/break phase cycle.
///
/// Timing is **deadline-based, not tick-based**: the engine stores the
/// moment the phase ends and derives `remaining` from the wall clock on
/// each tick. A counter decremented by 1 every second drifts whenever
/// the run loop is busy or the app is suspended — a 25-minute block can
/// finish a minute late. Comparing against a stored `Date` is accurate
/// regardless of how irregularly the tick actually fires.
@MainActor
final class FocusSessionEngine: ObservableObject {

    @Published private(set) var phase: FocusPhase = .focus
    @Published private(set) var remaining: TimeInterval = 0
    @Published private(set) var isRunning = false
    @Published private(set) var isPaused = false
    @Published private(set) var completedFocusRounds = 0

    /// Fires when a phase reaches its end, or when the user stops early.
    /// `completedFully` distinguishes the two.
    var onPhaseEnded: ((FocusPhase, _ actualDuration: TimeInterval, _ completedFully: Bool) -> Void)?

    private var configuration: FocusConfiguration = .pomodoro
    private var phaseStartedAt: Date?
    private var deadline: Date?
    private var pausedRemaining: TimeInterval?
    private var tickTask: Task<Void, Never>?

    var plannedDuration: TimeInterval {
        configuration.duration(for: phase)
    }

    var progress: Double {
        guard plannedDuration > 0 else { return 0 }
        return 1 - (remaining / plannedDuration)
    }

    // MARK: - Control

    func start(configuration: FocusConfiguration) {
        self.configuration = configuration.sanitized
        completedFocusRounds = 0
        begin(phase: .focus)
    }

    func pause() {
        guard isRunning, !isPaused, let deadline else { return }
        pausedRemaining = max(0, deadline.timeIntervalSinceNow)
        isPaused = true
        tickTask?.cancel()
    }

    func resume() {
        guard isPaused, let paused = pausedRemaining else { return }
        deadline = Date().addingTimeInterval(paused)
        pausedRemaining = nil
        isPaused = false
        startTicking()
    }

    /// Stop early. Reports the phase as ended-but-incomplete rather than
    /// discarding it, so partial work still appears in the summary.
    func stop() {
        guard isRunning else { return }
        let elapsed = phaseStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        let endedPhase = phase

        teardown()
        onPhaseEnded?(endedPhase, elapsed, false)
    }

    /// Finish the current phase now and move to the next one.
    func skipToNextPhase() {
        guard isRunning else { return }
        let elapsed = phaseStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        advance(from: phase, actualDuration: elapsed, completedFully: false)
    }

    // MARK: - Private

    private func begin(phase newPhase: FocusPhase) {
        phase = newPhase
        let duration = configuration.duration(for: newPhase)

        phaseStartedAt = Date()
        deadline = Date().addingTimeInterval(duration)
        remaining = duration
        isRunning = true
        isPaused = false
        pausedRemaining = nil

        startTicking()
    }

    private func startTicking() {
        tickTask?.cancel()
        // `Task { }` inside a @MainActor type inherits main-actor isolation,
        // so `tick()` is called directly — no `await`, because there's no
        // actor hop to suspend on. Only `Task.sleep` actually suspends here.
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                self?.tick()
            }
        }
    }

    private func tick() {
        guard let deadline, isRunning, !isPaused else { return }

        remaining = max(0, deadline.timeIntervalSinceNow)

        if remaining <= 0 {
            let elapsed = configuration.duration(for: phase)
            advance(from: phase, actualDuration: elapsed, completedFully: true)
        }
    }

    private func advance(from endedPhase: FocusPhase, actualDuration: TimeInterval, completedFully: Bool) {
        tickTask?.cancel()

        if endedPhase == .focus && completedFully {
            completedFocusRounds += 1
        }

        onPhaseEnded?(endedPhase, actualDuration, completedFully)

        let next = nextPhase(after: endedPhase)
        begin(phase: next)
    }

    private func nextPhase(after phase: FocusPhase) -> FocusPhase {
        guard phase == .focus else { return .focus }

        let isLongBreakDue = completedFocusRounds > 0
            && completedFocusRounds % configuration.roundsBeforeLongBreak == 0

        return isLongBreakDue ? .longBreak : .shortBreak
    }

    private func teardown() {
        tickTask?.cancel()
        tickTask = nil
        isRunning = false
        isPaused = false
        deadline = nil
        phaseStartedAt = nil
        pausedRemaining = nil
        remaining = 0
    }
}
