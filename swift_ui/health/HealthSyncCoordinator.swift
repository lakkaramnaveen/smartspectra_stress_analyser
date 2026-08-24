import Foundation
import SwiftUI

/// Owns the health-export buffer: periodic 5-minute batching of heart
/// rate, breathing rate, and mindful-session intervals, plus manual
/// export.
///
/// `AppModel` composes this like every other coordinator. There is no
/// permission-request flow here, deliberately — HealthKit's permission
/// system doesn't exist on this platform to request, and simulating one
/// would tell the user something false about what just happened.
@MainActor
final class HealthSyncCoordinator: ObservableObject {

    @Published private(set) var pendingBatches: [HealthSyncBatch] = []
    @Published private(set) var pendingSampleCount: Int = 0
    @Published private(set) var lastExportedAt: Date?
    @Published private(set) var isExporting = false

    private var batcher: HealthSyncBatcher
    private let store: HealthSyncStoring
    private var tickTask: Task<Void, Never>?

    init(store: HealthSyncStoring? = nil, flushInterval: TimeInterval = 300) {
        let resolvedStore = store ?? FileHealthSyncStore()
        self.store = resolvedStore
        self.batcher = HealthSyncBatcher(flushInterval: flushInterval)
        self.pendingBatches = resolvedStore.loadQueue()
    }

    // MARK: - Lifecycle

    func startSession() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            // Checked every 30s rather than driven by an external timer
            // — the batcher itself decides whether the 5-minute interval
            // has actually elapsed, so this cadence only affects how
            // promptly a due flush is noticed, not correctness.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                self?.checkFlush()
            }
        }
    }

    func endSession() {
        tickTask?.cancel()
        tickTask = nil
        // Capture whatever accumulated even if under five minutes —
        // ending a session shouldn't discard a partial window.
        checkFlush(force: true)
    }

    // MARK: - Ingestion

    func noteHeartRate(_ bpm: Double) {
        batcher.noteHeartRate(bpm)
        pendingSampleCount = batcher.pendingCount
    }

    func noteRespiratoryRate(_ breathsPerMinute: Double) {
        batcher.noteRespiratoryRate(breathsPerMinute)
        pendingSampleCount = batcher.pendingCount
    }

    /// Called every tick with whether a mindful practice is active right
    /// now and, if so, a display name for it.
    func noteMindfulBoundary(active: Bool, source: String?) {
        batcher.noteMindfulSessionBoundary(active: active, source: source)
        pendingSampleCount = batcher.pendingCount
    }

    // MARK: - Export

    func exportNow() {
        guard !pendingBatches.isEmpty else { return }
        isExporting = true

        HealthSyncExporter.exportWithSavePanel(pendingBatches) { [weak self] success in
            guard let self else { return }
            self.isExporting = false
            guard success else { return }

            self.lastExportedAt = Date()
            self.pendingBatches.removeAll()
            self.persist()
        }
    }

    // MARK: - Private

    private func checkFlush(force: Bool = false) {
        guard let batch = batcher.flushIfDue(force: force) else {
            pendingSampleCount = batcher.pendingCount
            return
        }

        pendingBatches.append(batch)
        pendingSampleCount = batcher.pendingCount
        persist()
    }

    private func persist() {
        do {
            try store.saveQueue(pendingBatches)
        } catch {
            print("HealthSyncCoordinator: failed to persist queue — \(error.localizedDescription)")
        }
    }
}
