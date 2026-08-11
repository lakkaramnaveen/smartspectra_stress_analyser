import Foundation
import SwiftUI

/// Loads session history and computes insights from it.
///
/// The analysis itself runs off the main actor via `Task.detached`,
/// because aggregating a few hundred sessions means walking tens of
/// thousands of snapshots and running a lead-lag scan per session —
/// enough to drop frames if it happened inline on a view update.
@MainActor
final class InsightsViewModel: ObservableObject {

    enum LoadState: Equatable {
        case idle
        case loading
        /// Fewer than the minimum sessions needed to say anything useful.
        case needsMoreData(sessionsRecorded: Int, sessionsNeeded: Int)
        case ready
    }

    @Published private(set) var state: LoadState = .idle
    @Published private(set) var insights: [Insight] = []
    @Published private(set) var aggregates: InsightAggregates = .empty

    private let store: SessionStoring
    private let aggregator: SessionAggregator
    private let generator: InsightGenerator

    init(
        store: SessionStoring? = nil,
        aggregator: SessionAggregator = SessionAggregator(),
        generator: InsightGenerator = InsightGenerator()
    ) {
        self.store = store ?? FileSessionStore()
        self.aggregator = aggregator
        self.generator = generator
    }

    func refresh() async {
        state = .loading

        let summaries = store.loadSummaries()
        let minimum = generator.thresholds.minimumSessions

        guard summaries.count >= minimum else {
            insights = []
            aggregates = .empty
            state = .needsMoreData(
                sessionsRecorded: summaries.count,
                sessionsNeeded: minimum
            )
            return
        }

        // Load on the main actor (the store isn't Sendable), then hand
        // the resulting value types to a detached task for the heavy
        // arithmetic.
        let recordings = summaries.compactMap { try? store.load(id: $0.id) }

        let aggregator = self.aggregator
        let generator = self.generator

        let result = await Task.detached(priority: .userInitiated) { () -> (InsightAggregates, [Insight]) in
            let aggregates = aggregator.aggregate(recordings)
            let insights = generator.generate(from: aggregates)
            return (aggregates, insights)
        }.value

        aggregates = result.0
        insights = result.1
        state = .ready
    }
}
