import Foundation

/// Calendar-aware streak calculation with a built-in grace day.
///
/// The forgiveness is the point. An unforgiving streak on a stress app
/// creates exactly the pressure the app exists to reduce — and the most
/// common abandonment pattern for habit tools is a user breaking a long
/// chain, feeling there's nothing left to protect, and never returning.
/// One free missed day per streak makes the mechanic motivating without
/// making it a source of anxiety.
struct StreakCalculator: Sendable {

    /// How many consecutive missed days a streak can survive.
    let graceDays: Int

    /// Grace is replenished after this many consecutive qualifying days,
    /// so a long streak isn't permanently fragile after one use.
    let graceReplenishInterval: Int

    init(graceDays: Int = 1, graceReplenishInterval: Int = 7) {
        self.graceDays = graceDays
        self.graceReplenishInterval = graceReplenishInterval
    }

    /// Recompute the full streak from a set of qualifying days.
    ///
    /// Recomputing from history rather than incrementing a counter means
    /// the streak is always consistent with the underlying sessions —
    /// no drift from a missed update, a crash mid-write, or a deleted
    /// session.
    func streak(
        from qualifyingDays: Set<Date>,
        asOf today: Date = Date(),
        calendar: Calendar = .current
    ) -> StreakState {
        guard !qualifyingDays.isEmpty else { return .empty }

        let normalizedToday = calendar.startOfDay(for: today)
        let sortedDays = qualifyingDays
            .map { calendar.startOfDay(for: $0) }
            .sorted()

        // --- Best streak ever, walking forward through history ---
        var bestRun = 0
        var currentRun = 0
        var graceInHand = graceDays
        var previousDay: Date?

        for day in sortedDays {
            defer { previousDay = day }

            guard let previous = previousDay else {
                currentRun = 1
                bestRun = max(bestRun, currentRun)
                continue
            }

            let gap = calendar.dateComponents([.day], from: previous, to: day).day ?? 0

            switch gap {
            case 0:
                continue                      // same day, already counted
            case 1:
                currentRun += 1
                if currentRun % graceReplenishInterval == 0 {
                    graceInHand = graceDays
                }
            case 2...(1 + graceDays):
                // Within grace: streak survives, grace is spent.
                if graceInHand > 0 {
                    graceInHand -= 1
                    currentRun += 1
                } else {
                    currentRun = 1
                }
            default:
                currentRun = 1
                graceInHand = graceDays
            }

            bestRun = max(bestRun, currentRun)
        }

        // --- Is the run still live as of today? ---
        guard let lastDay = sortedDays.last else { return .empty }
        let daysSinceLast = calendar.dateComponents([.day], from: lastDay, to: normalizedToday).day ?? 0

        // Today not yet logged is not a broken streak — the day isn't
        // over. Only a fully elapsed missed day counts against it.
        let stillLive = daysSinceLast <= (1 + graceDays)

        return StreakState(
            current: stillLive ? currentRun : 0,
            best: bestRun,
            lastQualifyingDay: lastDay,
            graceDaysRemaining: graceInHand
        )
    }

    /// Distinct days in the current calendar week that have a qualifying
    /// session. Used for `activeDays` goals.
    func activeDaysThisWeek(
        from qualifyingDays: Set<Date>,
        asOf today: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: today) else { return 0 }
        return qualifyingDays
            .map { calendar.startOfDay(for: $0) }
            .filter { week.contains($0) }
            .count
    }
}
