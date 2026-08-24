import Foundation
import SwiftUI

/// Owns the sleep log and the analysis drawn from it.
///
/// Analysis runs off the main actor: joining every logged night against
/// every session's snapshots is the same order of work as the insights
/// aggregation, and doing it inline on a view update would drop frames.
@MainActor
final class SleepCoordinator: ObservableObject {

    @Published private(set) var entries: [SleepEntry] = []
    @Published private(set) var association: SleepAssociation = .none
    @Published private(set) var dayparts: [DaypartStress] = []
    @Published private(set) var isAnalysing = false

    private let store: SleepStoring
    private let sessionStore: SessionStoring
    private let analyzer: SleepStressAnalyzer

    init(
        store: SleepStoring? = nil,
        sessionStore: SessionStoring? = nil,
        analyzer: SleepStressAnalyzer = SleepStressAnalyzer()
    ) {
        let resolvedStore = store ?? FileSleepStore()
        self.store = resolvedStore
        self.sessionStore = sessionStore ?? FileSessionStore()
        self.analyzer = analyzer
        self.entries = resolvedStore.load()
    }

    // MARK: - Today

    private var today: Date { Calendar.current.startOfDay(for: Date()) }

    /// Whether the user has already logged this morning.
    var hasLoggedToday: Bool {
        entries.contains { $0.forDay == today }
    }

    var todaysEntry: SleepEntry? {
        entries.first { $0.forDay == today }
    }

    /// Most recent nights, newest first.
    func recent(_ count: Int = 14) -> [SleepEntry] {
        Array(entries.prefix(count))
    }

    // MARK: - Logging

    /// Record (or replace) a night.
    ///
    /// Replacing rather than appending means a user correcting a
    /// mis-entered figure doesn't end up with two nights for one day,
    /// which would quietly skew every downstream average.
    func log(hours: Double, quality: RestQuality, forDay day: Date = Date()) {
        let normalisedDay = Calendar.current.startOfDay(for: day)
        let clampedHours = min(max(hours, SleepEntry.hoursRange.lowerBound), SleepEntry.hoursRange.upperBound)

        entries.removeAll { $0.forDay == normalisedDay }
        entries.append(
            SleepEntry(forDay: normalisedDay, hours: clampedHours, quality: quality)
        )
        entries.sort { $0.forDay > $1.forDay }

        persist()
        Task { await analyse() }
    }

    func delete(_ entry: SleepEntry) {
        entries.removeAll { $0.id == entry.id }
        persist()
        Task { await analyse() }
    }

    // MARK: - Analysis

    func analyse() async {
        isAnalysing = true
        defer { isAnalysing = false }

        // Load on the main actor (the store isn't Sendable), then hand
        // the resulting value types to a detached task.
        let recordings = sessionStore.loadSummaries()
            .compactMap { try? sessionStore.load(id: $0.id) }
        let loggedEntries = entries
        let analyzer = self.analyzer

        let result = await Task.detached(priority: .utility) {
            (
                analyzer.associate(entries: loggedEntries, recordings: recordings),
                analyzer.dayparts(from: recordings)
            )
        }.value

        association = result.0
        dayparts = result.1
    }

    // MARK: - Private

    private func persist() {
        do {
            try store.save(entries)
        } catch {
            print("SleepCoordinator: failed to persist — \(error.localizedDescription)")
        }
    }
}
