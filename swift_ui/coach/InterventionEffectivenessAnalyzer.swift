import Foundation

/// Detects when a breathing or meditation session starts and ends, and
/// turns each completed one into an `EffectivenessRecord`.
///
/// Pure and UI-free — same shape as `RecoveryDetector`. Deliberately
/// watches state it's *handed* on each call rather than holding
/// references to `BreathingCoordinator` / `MeditationCoordinator`:
/// `recomputeDerivedState` already knows which technique or meditation
/// is active on every tick, so this only needs the current identity and
/// the current score, which keeps it independently testable and avoids
/// a second coupling to either coordinator.
struct InterventionEffectivenessAnalyzer {

    /// Ambient stress samples kept regardless of intervention state, so
    /// a "before" baseline already exists the instant one starts rather
    /// than needing to be collected retroactively.
    private var ambient = RollingBuffer<Double>(capacity: 12)

    private var activeKind: InterventionKind?
    private var activeStartedAt: Date?
    private var activeStressBefore: Double?
    private var activeSamples: [Double] = []

    /// Samples needed inside a window before it's recorded at all. A
    /// session dismissed after four seconds says nothing about the
    /// technique — see the note in `closeOut`.
    private let minimumSamples = 5

    /// Feed the current score and whichever intervention is active right
    /// now (`nil` if none). Returns a completed record the instant a
    /// session just ended, otherwise `nil`.
    mutating func ingest(
        score: Double,
        activeKind newKind: InterventionKind?,
        now: Date = Date()
    ) -> EffectivenessRecord? {
        defer { ambient.append(score) }

        // Still idle, or still inside the same session — accumulate and
        // return early.
        if newKind?.key == activeKind?.key {
            if activeKind != nil { activeSamples.append(score) }
            return nil
        }

        // Identity changed: close out whatever was running before
        // opening (or not opening) the next one.
        var completed: EffectivenessRecord?
        if let kind = activeKind, let startedAt = activeStartedAt,
           let before = activeStressBefore {
            completed = closeOut(kind: kind, startedAt: startedAt, before: before, now: now)
        }

        if let newKind {
            activeKind = newKind
            activeStartedAt = now
            // Ambient average if we have one, otherwise this sample —
            // covers the very first tick of the whole app run.
            activeStressBefore = ambient.elements.isEmpty ? score : ambient.elements.average
            activeSamples = [score]
        } else {
            activeKind = nil
            activeStartedAt = nil
            activeStressBefore = nil
            activeSamples = []
        }

        return completed
    }

    /// Ends the current session without waiting for the next state
    /// change to notice — used when the caller already knows a session
    /// has closed (e.g. the app stopped monitoring entirely) rather than
    /// inferring it from the next `ingest` call, which may never come.
    @discardableResult
    mutating func forceClose(now: Date = Date()) -> EffectivenessRecord? {
        guard let kind = activeKind, let startedAt = activeStartedAt,
              let before = activeStressBefore else { return nil }

        let record = closeOut(kind: kind, startedAt: startedAt, before: before, now: now)
        activeKind = nil
        activeStartedAt = nil
        activeStressBefore = nil
        activeSamples = []
        return record
    }

    private func closeOut(
        kind: InterventionKind,
        startedAt: Date,
        before: Double,
        now: Date
    ) -> EffectivenessRecord? {
        guard activeSamples.count >= minimumSamples else { return nil }

        // "After" is the mean of the closing third of the session, not
        // the single final reading — one noisy sample right at the
        // boundary shouldn't decide the whole record. Same windowed
        // approach as `MeditationStressAnalyzer.compare`.
        let windowSize = max(activeSamples.count / 3, 2)
        let after = Array(activeSamples.suffix(windowSize)).average

        return EffectivenessRecord(
            kind: kind,
            startedAt: startedAt,
            duration: now.timeIntervalSince(startedAt),
            stressBefore: before,
            stressAfter: after,
            sampleCount: activeSamples.count
        )
    }
}
