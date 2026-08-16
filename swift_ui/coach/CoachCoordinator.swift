import Foundation
import SwiftUI

/// Owns intervention-effectiveness tracking and the recommendations
/// derived from it.
///
/// `AppModel` composes this the same way it composes every other
/// coordinator: one property, `ingest` fed from the single stress
/// fan-out point, `flush` called on session end.
@MainActor
final class CoachCoordinator: ObservableObject {

    @Published private(set) var recommendations: [CoachRecommendation] = []
    @Published private(set) var ranked: [TechniqueEffectiveness] = []
    @Published private(set) var totalRecords: Int = 0
    @Published private(set) var isAnalysing = false

    private var analyzer = InterventionEffectivenessAnalyzer()
    private let engine: CoachEngine
    private let store: CoachStoring
    private let sessionStore: SessionStoring
    private let sessionAggregator = SessionAggregator()

    private var records: [EffectivenessRecord]

    init(
        store: CoachStoring? = nil,
        sessionStore: SessionStoring? = nil,
        engine: CoachEngine = CoachEngine()
    ) {
        let resolvedStore = store ?? FileCoachStore()
        self.store = resolvedStore
        self.sessionStore = sessionStore ?? FileSessionStore()
        self.engine = engine

        let loaded = resolvedStore.load()
        self.records = loaded
        self.ranked = engine.effectiveness(from: loaded)
        self.totalRecords = loaded.count
    }

    // MARK: - Ingestion

    /// Feed the current stress score plus whichever intervention (if
    /// any) is active right now. Safe to call on every tick alongside
    /// the other coordinators — no-ops unless a session just closed.
    func ingest(score: Double, activeIntervention: InterventionKind?) {
        guard let record = analyzer.ingest(score: score, activeKind: activeIntervention) else {
            return
        }
        append(record)
    }

    /// Closes out a session that's mid-flight when monitoring stops
    /// entirely (e.g. the user hits Stop with the pacer still up), so
    /// that data isn't silently discarded rather than recorded.
    func flush() {
        guard let record = analyzer.forceClose() else { return }
        append(record)
    }

    // MARK: - Analysis

    func refresh() async {
        isAnalysing = true
        defer { isAnalysing = false }

        let recordings = sessionStore.loadSummaries()
            .compactMap { try? sessionStore.load(id: $0.id) }
        let currentRecords = records
        let engine = self.engine
        let aggregator = self.sessionAggregator

        let result = await Task.detached(priority: .utility) {
            () -> ([TechniqueEffectiveness], [CoachRecommendation]) in
            let aggregates = aggregator.aggregate(recordings)
            let rankedResult = engine.effectiveness(from: currentRecords)
            let recs = engine.recommendations(from: currentRecords, hourBuckets: aggregates.hourBuckets)
            return (rankedResult, recs)
        }.value

        ranked = result.0
        recommendations = result.1
    }

    // MARK: - Private

    private func append(_ record: EffectivenessRecord) {
        records.append(record)
        totalRecords = records.count
        persist()
        Task { await refresh() }
    }

    private func persist() {
        do {
            try store.save(records)
        } catch {
            print("CoachCoordinator: failed to persist — \(error.localizedDescription)")
        }
    }
}
