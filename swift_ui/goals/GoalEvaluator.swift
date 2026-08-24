import Foundation

// MARK: - Configuration

struct GoalEvaluationConfig: Sendable {
    /// Stress score below which the user counts as "calm" for the
    /// purposes of sustained-calm and recovery goals. Matches the
    /// `.calm` band in `StressLevel.classify`.
    var calmThreshold: Double = 0.30

    /// Score above which a moment counts as a peak, for recovery timing.
    var peakThreshold: Double = 0.70

    /// Ceiling on how much session time any single goal can require.
    ///
    /// This exists to stop the goal system rewarding compulsive
    /// self-monitoring. A "record a 4-hour session" goal would be
    /// trivial to add and actively harmful — sitting in front of a
    /// stress monitor all afternoon is not a wellness outcome. Any goal
    /// asking for more than this is clamped.
    var maximumGoalSessionSeconds: TimeInterval = 30 * 60

    static let `default` = GoalEvaluationConfig()
}

// MARK: - Session Facts

/// The derived facts about one session that goals are measured against.
/// Computed once per session rather than re-walking snapshots for each
/// goal.
struct SessionFacts: Sendable {
    let durationSeconds: TimeInterval
    let peakStress: Double
    let longestCalmRunSeconds: TimeInterval
    let fastestRecoverySeconds: TimeInterval?
    let day: Date   // start-of-day, for streak/active-day counting
}

// MARK: - Evaluator

/// Pure functions turning session recordings into goal progress.
///
/// No storage, no UI, no actor isolation — same shape as
/// `StressScoringEngine` and `CorrelationAnalyzer`, and testable with
/// plain input/output assertions.
struct GoalEvaluator: Sendable {
    let config: GoalEvaluationConfig

    init(config: GoalEvaluationConfig = .default) {
        self.config = config
    }

    // MARK: Facts extraction

    func facts(for recording: SessionRecording, calendar: Calendar = .current) -> SessionFacts {
        let sorted = recording.snapshots.sorted { $0.timestamp < $1.timestamp }

        return SessionFacts(
            durationSeconds: recording.duration,
            peakStress: recording.peakStress,
            longestCalmRunSeconds: longestCalmRun(in: sorted),
            fastestRecoverySeconds: fastestRecovery(in: sorted),
            day: calendar.startOfDay(for: recording.startedAt)
        )
    }

    /// Longest continuous stretch below the calm threshold.
    ///
    /// Measured in elapsed time between snapshots rather than snapshot
    /// count, because the sampling cadence isn't perfectly even — a gap
    /// in the feed shouldn't silently inflate or deflate a calm run.
    func longestCalmRun(in sorted: [SessionSnapshot]) -> TimeInterval {
        guard sorted.count >= 2 else { return 0 }

        var longest: TimeInterval = 0
        var runStart: Date?

        for (index, snapshot) in sorted.enumerated() {
            let isCalm = snapshot.stressScore <= config.calmThreshold

            if isCalm {
                if runStart == nil { runStart = snapshot.timestamp }

                // Close out the run at the final snapshot too, otherwise
                // a session ending while calm loses its last stretch.
                if index == sorted.count - 1, let start = runStart {
                    longest = max(longest, snapshot.timestamp.timeIntervalSince(start))
                }
            } else if let start = runStart {
                longest = max(longest, snapshot.timestamp.timeIntervalSince(start))
                runStart = nil
            }
        }

        return longest
    }

    /// Shortest time from crossing above `peakThreshold` back down below
    /// `calmThreshold`. Returns `nil` if no full peak-to-calm cycle
    /// occurred — an incomplete recovery shouldn't be scored as an
    /// infinitely slow one.
    func fastestRecovery(in sorted: [SessionSnapshot]) -> TimeInterval? {
        guard sorted.count >= 2 else { return nil }

        var fastest: TimeInterval?
        var peakAt: Date?

        for snapshot in sorted {
            if snapshot.stressScore >= config.peakThreshold {
                // Keep the earliest moment of the current peak episode.
                if peakAt == nil { peakAt = snapshot.timestamp }
            } else if snapshot.stressScore <= config.calmThreshold, let start = peakAt {
                let elapsed = snapshot.timestamp.timeIntervalSince(start)
                fastest = min(fastest ?? elapsed, elapsed)
                peakAt = nil
            }
        }

        return fastest
    }

    // MARK: Progress

    /// Progress for one goal, given this session plus weekly context.
    ///
    /// - Parameters:
    ///   - activeDaysThisWeek: distinct days with a qualifying session.
    ///   - breathingThisWeek: breathing interventions completed this week.
    func progress(
        for goal: Goal,
        facts: SessionFacts?,
        activeDaysThisWeek: Int,
        breathingThisWeek: Int
    ) -> GoalProgress {
        switch goal.kind {

        case .completeSession(let minimumSeconds):
            let target = min(minimumSeconds, config.maximumGoalSessionSeconds)
            let achieved = facts?.durationSeconds ?? 0
            return GoalProgress(
                goal: goal,
                fraction: clamped(achieved / target),
                statusText: "\(DurationFormatter.mmss(achieved)) of \(DurationFormatter.mmss(target))"
            )

        case .completeBreathing(let count):
            return GoalProgress(
                goal: goal,
                fraction: clamped(Double(breathingThisWeek) / Double(max(count, 1))),
                statusText: "\(min(breathingThisWeek, count)) of \(count)"
            )

        case .activeDays(let count):
            return GoalProgress(
                goal: goal,
                fraction: clamped(Double(activeDaysThisWeek) / Double(max(count, 1))),
                statusText: "\(min(activeDaysThisWeek, count)) of \(count) days"
            )

        case .sustainedCalm(let seconds):
            let target = min(seconds, config.maximumGoalSessionSeconds)
            let achieved = facts?.longestCalmRunSeconds ?? 0
            return GoalProgress(
                goal: goal,
                fraction: clamped(achieved / target),
                statusText: "\(DurationFormatter.mmss(achieved)) of \(DurationFormatter.mmss(target))"
            )

        case .fastRecovery(let withinSeconds):
            guard let recovery = facts?.fastestRecoverySeconds else {
                return GoalProgress(
                    goal: goal,
                    fraction: 0,
                    statusText: "No peak to recover from"  // not a failure
                )
            }
            // Faster is better, so progress inverts: hitting the target
            // exactly is 1.0, and anything faster stays at 1.0.
            let fraction = clamped(withinSeconds / max(recovery, 0.001))
            return GoalProgress(
                goal: goal,
                fraction: fraction,
                statusText: "\(Int(recovery))s (target \(Int(withinSeconds))s)"
            )
        }
    }

    // MARK: Helpers

    private func clamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
