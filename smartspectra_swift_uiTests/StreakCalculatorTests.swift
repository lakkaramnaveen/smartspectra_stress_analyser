import XCTest
@testable import smartspectra_swift_ui

final class StreakCalculatorTests: XCTestCase {

    /// Fixed, locale-independent calendar so these tests don't depend on
    /// the machine's timezone or week-start convention.
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2 // Monday
        return calendar
    }()

    private func day(_ offsetDays: Int, from reference: Date = Date(timeIntervalSince1970: 0)) -> Date {
        calendar.date(byAdding: .day, value: offsetDays, to: reference)!
    }

    // MARK: - streak: empty and trivial cases

    func test_streak_emptyInput_returnsEmptyState() {
        let calculator = StreakCalculator()
        XCTAssertEqual(calculator.streak(from: [], asOf: day(0), calendar: calendar), .empty)
    }

    func test_streak_singleQualifyingDay_countsAsOne() {
        let calculator = StreakCalculator()
        let state = calculator.streak(from: [day(0)], asOf: day(0), calendar: calendar)
        XCTAssertEqual(state.current, 1)
        XCTAssertEqual(state.best, 1)
        XCTAssertEqual(state.lastQualifyingDay, calendar.startOfDay(for: day(0)))
    }

    // MARK: - streak: consecutive days

    func test_streak_consecutiveDays_buildsCurrentAndBest() {
        let calculator = StreakCalculator()
        let days: Set<Date> = [day(0), day(1), day(2)]
        let state = calculator.streak(from: days, asOf: day(2), calendar: calendar)
        XCTAssertEqual(state.current, 3)
        XCTAssertEqual(state.best, 3)
    }

    // MARK: - streak: grace day

    func test_streak_oneMissedDay_survivesViaGrace() {
        // day0, day1, [day2 missing], day3 — a single missed day is
        // exactly what the default one-day grace is meant to absorb.
        let calculator = StreakCalculator(graceDays: 1, graceReplenishInterval: 7)
        let days: Set<Date> = [day(0), day(1), day(3)]
        let state = calculator.streak(from: days, asOf: day(3), calendar: calendar)
        XCTAssertEqual(state.current, 3)
        XCTAssertEqual(state.best, 3)
        XCTAssertEqual(state.graceDaysRemaining, 0, "the single grace day should have been spent")
    }

    func test_streak_gapBeyondGrace_resetsCurrentRun() {
        // day0, day1, [days 2-3 missing], day4 — a two-day gap exceeds the
        // one-day grace, so the run restarts rather than surviving.
        let calculator = StreakCalculator(graceDays: 1, graceReplenishInterval: 7)
        let days: Set<Date> = [day(0), day(1), day(4)]
        let state = calculator.streak(from: days, asOf: day(4), calendar: calendar)
        XCTAssertEqual(state.current, 1)
        XCTAssertEqual(state.best, 2, "the earlier two-day run should still be the best on record")
        XCTAssertEqual(state.graceDaysRemaining, 1, "grace resets along with the run")
    }

    func test_streak_graceIsReplenishedAfterInterval() {
        // With a short replenish interval, spending grace once shouldn't
        // leave a long streak permanently fragile.
        let calculator = StreakCalculator(graceDays: 1, graceReplenishInterval: 3)
        // day0, [day1 missing], day2 (grace spent, run=2),
        // day3 (run=3 -> 3 % 3 == 0 -> grace replenished),
        // [day4 missing], day5 (grace spent again, run=4).
        let days: Set<Date> = [day(0), day(2), day(3), day(5)]
        let state = calculator.streak(from: days, asOf: day(5), calendar: calendar)
        XCTAssertEqual(state.current, 4)
        XCTAssertEqual(state.graceDaysRemaining, 0)
    }

    // MARK: - streak: liveness as of "today"

    func test_streak_todayNotYetLogged_isNotConsideredBroken() {
        let calculator = StreakCalculator()
        let days: Set<Date> = [day(0), day(1)]
        // "Today" is the day after the last logged session — the day
        // itself isn't over, so this shouldn't read as a broken streak.
        let state = calculator.streak(from: days, asOf: day(2), calendar: calendar)
        XCTAssertEqual(state.current, 2)
    }

    func test_streak_goneStaleBeyondGraceWindow_readsAsZeroButKeepsBest() {
        let calculator = StreakCalculator(graceDays: 1, graceReplenishInterval: 7)
        let days: Set<Date> = [day(0)]
        // Three full days have elapsed since the only qualifying day —
        // well past the grace window — so the current streak is gone.
        let state = calculator.streak(from: days, asOf: day(3), calendar: calendar)
        XCTAssertEqual(state.current, 0)
        XCTAssertEqual(state.best, 1)
        XCTAssertEqual(state.lastQualifyingDay, calendar.startOfDay(for: day(0)))
    }

    // MARK: - activeDaysThisWeek

    func test_activeDaysThisWeek_countsOnlyDaysWithinTheCalendarWeek() {
        let calculator = StreakCalculator()
        // Jan 1, 2024 is a Monday; with firstWeekday = Monday the week
        // containing it runs Jan 1 through Jan 7 inclusive.
        var components = DateComponents()
        components.year = 2024
        components.month = 1
        components.day = 1
        let monday = calendar.date(from: components)!
        let wednesday = calendar.date(byAdding: .day, value: 2, to: monday)!
        // `DateInterval.contains(_:)` is inclusive of both boundaries, so
        // the week's end instant (`monday + 7 days`, i.e. next Monday
        // 00:00) would itself still count as "in" this week — picking a
        // day clearly past that avoids relying on that boundary detail.
        let tuesdayNextWeek = calendar.date(byAdding: .day, value: 8, to: monday)!
        let sundayPreviousWeek = calendar.date(byAdding: .day, value: -1, to: monday)!

        let days: Set<Date> = [monday, wednesday, tuesdayNextWeek, sundayPreviousWeek]
        let count = calculator.activeDaysThisWeek(from: days, asOf: wednesday, calendar: calendar)
        XCTAssertEqual(count, 2, "only Monday and Wednesday fall inside the same week as the reference date")
    }
}
