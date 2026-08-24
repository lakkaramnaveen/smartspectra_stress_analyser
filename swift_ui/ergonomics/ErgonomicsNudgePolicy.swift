import Foundation

/// Decides when an ergonomics reminder is worth surfacing.
///
/// Separated from measurement (`GazePostureAnalyzer`) and from delivery
/// (the coordinator) for the same reason `InterventionAlertPolicy` is
/// separate from `StressTrendAnalyzer`: "should we interrupt someone" is
/// a distinct judgement from "what is happening", and it's the part most
/// likely to need tuning after real use.
struct ErgonomicsNudgePolicy {

    let config: ErgonomicsConfig

    private var lastNudgeAt: Date?
    private var lastScreenBreakNudgeMinute: Int = 0
    private var lastNeckNudgeMinute: Int = 0
    private var lastEyeRestAt: Date?

    init(config: ErgonomicsConfig = .default) {
        self.config = config
    }

    /// Evaluate current stats and return a nudge if one is due.
    ///
    /// Returns at most one nudge per call, and never more than one per
    /// cooldown window regardless of how many conditions are met. Three
    /// reminders arriving together would read as nagging, and a user who
    /// starts dismissing them reflexively gets nothing from any of them.
    mutating func evaluate(
        stats: ErgonomicsStats,
        now: Date = Date(),
        suppressed: Bool
    ) -> ErgonomicsNudge? {
        guard config.isEnabled, !suppressed else { return nil }

        // Never nudge on data we don't trust.
        guard stats.quality != .unusable else { return nil }

        if let lastNudgeAt,
           now.timeIntervalSince(lastNudgeAt) < TimeInterval(config.nudgeCooldownMinutes * 60) {
            return nil
        }

        // Ordered by how much the user is likely to benefit: a real
        // break subsumes eye rest and neck relief, so it's checked first.
        if let nudge = screenBreakNudge(stats: stats, now: now) { return record(nudge, at: now) }
        if let nudge = neckFlexionNudge(stats: stats, now: now) { return record(nudge, at: now) }
        if let nudge = eyeRestNudge(stats: stats, now: now) { return record(nudge, at: now) }

        return nil
    }

    mutating func reset() {
        lastNudgeAt = nil
        lastScreenBreakNudgeMinute = 0
        lastNeckNudgeMinute = 0
        lastEyeRestAt = nil
    }

    /// Called when the user marks a break as taken.
    mutating func breakTaken(at now: Date = Date()) {
        lastEyeRestAt = now
        lastScreenBreakNudgeMinute = 0
        lastNeckNudgeMinute = 0
    }

    // MARK: - Private

    private mutating func record(_ nudge: ErgonomicsNudge, at now: Date) -> ErgonomicsNudge {
        lastNudgeAt = now
        return nudge
    }

    private mutating func screenBreakNudge(stats: ErgonomicsStats, now: Date) -> ErgonomicsNudge? {
        let minutes = Int(stats.timeSinceBreakSeconds / 60)
        guard minutes >= config.screenBreakMinutes,
              minutes > lastScreenBreakNudgeMinute else { return nil }

        lastScreenBreakNudgeMinute = minutes

        return ErgonomicsNudge(
            kind: .screenBreak(minutes: minutes),
            title: "You've been at this \(minutes) minutes",
            // Suggestion, not instruction. The user knows their own
            // workload better than the app does, and phrasing that
            // acknowledges that is the difference between a reminder
            // people keep on and one they switch off.
            body: "A few minutes away from the screen would be a good idea if you can spare them.",
            raisedAt: now
        )
    }

    private mutating func neckFlexionNudge(stats: ErgonomicsStats, now: Date) -> ErgonomicsNudge? {
        let minutes = Int(stats.downwardGazeSeconds / 60)
        guard minutes >= config.neckFlexionMinutes,
              minutes > lastNeckNudgeMinute else { return nil }

        lastNeckNudgeMinute = minutes

        return ErgonomicsNudge(
            kind: .neckFlexion(minutes: minutes),
            title: "\(minutes) minutes looking downward",
            body: "Worth a stretch, or raising whatever you're reading closer to eye level.",
            raisedAt: now
        )
    }

    private mutating func eyeRestNudge(stats: ErgonomicsStats, now: Date) -> ErgonomicsNudge? {
        guard config.eyeRestEnabled else { return nil }

        let since = lastEyeRestAt ?? Date(timeIntervalSince1970: 0)
        let elapsed = now.timeIntervalSince(since)
        guard elapsed >= TimeInterval(config.eyeRestMinutes * 60) else { return nil }

        // Don't fire in the first minutes of a session — an eye-rest
        // reminder twenty seconds after sitting down is just noise.
        guard stats.screenTimeSeconds >= TimeInterval(config.eyeRestMinutes * 60) else { return nil }

        lastEyeRestAt = now

        return ErgonomicsNudge(
            kind: .eyeRest,
            title: "Give your eyes a moment",
            body: "Look at something far away for twenty seconds or so — out a window is ideal.",
            raisedAt: now
        )
    }
}
