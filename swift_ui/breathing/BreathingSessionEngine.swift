import Foundation
import SwiftUI

/// Sequences a breathing technique through its phases and publishes the
/// current state for the pacer view to animate against.
///
/// Replaces the chain of `DispatchQueue.main.asyncAfter` calls in the
/// original pacer. Those were untestable, un-cancellable, and hardcoded
/// to one 4-6 pattern; a structured `Task` loop handles arbitrary phase
/// sequences and stops cleanly when the view disappears.
@MainActor
final class BreathingSessionEngine: ObservableObject {

    @Published private(set) var technique: BreathingTechnique?
    @Published private(set) var currentPhase: BreathPhase = .inhale
    @Published private(set) var phaseDuration: TimeInterval = 0
    @Published private(set) var completedCycles: Int = 0
    @Published private(set) var isRunning = false

    /// Fires when the full cycle count finishes. Not called when the
    /// user exits early — a technique abandoned partway through isn't a
    /// completion, and counting it would hollow out the tracking.
    var onCompleted: ((BreathingTechnique) -> Void)?

    private var sessionTask: Task<Void, Never>?

    var totalCycles: Int { technique?.cycleCount ?? 0 }

    var cycleProgress: Double {
        guard totalCycles > 0 else { return 0 }
        return Double(completedCycles) / Double(totalCycles)
    }

    // MARK: - Control

    func start(_ technique: BreathingTechnique) {
        stop()

        // Sanitize at the boundary — a pattern loaded from disk or an
        // older build shouldn't be able to bypass the safe ranges.
        let safe = technique.sanitized

        self.technique = safe
        completedCycles = 0
        isRunning = true

        sessionTask = Task { [weak self] in
            await self?.run(safe)
        }
    }

    func stop() {
        sessionTask?.cancel()
        sessionTask = nil
        isRunning = false
    }

    /// Restart the current technique from cycle zero.
    func restart() {
        guard let technique else { return }
        start(technique)
    }

    // MARK: - Loop

    private func run(_ technique: BreathingTechnique) async {
        let phases = technique.pattern.activePhases
        guard !phases.isEmpty else { return }

        for _ in 0..<technique.cycleCount {
            for (phase, duration) in phases {
                guard !Task.isCancelled else { return }

                currentPhase = phase
                phaseDuration = duration

                try? await Task.sleep(for: .seconds(duration))
                guard !Task.isCancelled else { return }
            }

            completedCycles += 1
        }

        isRunning = false
        onCompleted?(technique)
    }
}
