import Foundation

/// Accumulates readings and groups them into `HealthSyncBatch`es on a
/// periodic cadence.
///
/// Pure and UI-free — same shape as `InterventionEffectivenessAnalyzer`.
/// Nothing here touches HealthKit, the filesystem, or SwiftUI; it just
/// decides *what would be sent, and when*, which is the part of "sync
/// every 5 minutes" that's actually implementable on this platform.
struct HealthSyncBatcher {

    private var pendingHeartRate: [HeartRateSample] = []
    private var pendingRespiratory: [RespiratoryRateSample] = []
    private var pendingMindful: [MindfulInterval] = []

    private var openMindfulStart: Date?
    private var openMindfulSource: String?

    private var lastHeartRateAt: Date?
    private var lastRespiratoryAt: Date?
    private var lastFlushAt: Date

    private let flushInterval: TimeInterval

    /// Minimum gap between recorded readings of the same kind. The SDK
    /// can deliver a metrics update several times a second; recording
    /// every one would make the export file enormous without adding
    /// anything a HealthKit reader could use — Health's own heart-rate
    /// samples are typically seconds apart even from a Watch, not
    /// sub-second.
    private let minimumSampleInterval: TimeInterval

    /// Mindful intervals shorter than this are dropped rather than
    /// recorded. A three-second glance at the breathing pacer before
    /// dismissing it isn't a mindful session by any reasonable
    /// definition, and HealthKit's own Mindful Minutes feature discounts
    /// intervals this short as well.
    private let minimumMindfulDuration: TimeInterval = 30

    init(
        flushInterval: TimeInterval = 300,
        minimumSampleInterval: TimeInterval = 5,
        now: Date = Date()
    ) {
        self.flushInterval = flushInterval
        self.minimumSampleInterval = minimumSampleInterval
        self.lastFlushAt = now
    }

    // MARK: - Ingestion

    mutating func noteHeartRate(_ bpm: Double, at now: Date = Date()) {
        guard bpm > 0 else { return }  // guards against "--" placeholder parses
        guard shouldRecord(lastHeartRateAt, now: now) else { return }
        lastHeartRateAt = now
        pendingHeartRate.append(HeartRateSample(bpm: bpm, timestamp: now))
    }

    mutating func noteRespiratoryRate(_ breathsPerMinute: Double, at now: Date = Date()) {
        guard breathsPerMinute > 0 else { return }
        guard shouldRecord(lastRespiratoryAt, now: now) else { return }
        lastRespiratoryAt = now
        pendingRespiratory.append(RespiratoryRateSample(breathsPerMinute: breathsPerMinute, timestamp: now))
    }

    /// Called on every tick with whether a mindful practice (breathing
    /// or meditation) is currently active. Safe to call continuously —
    /// only the transitions matter, both directions are idempotent while
    /// state doesn't change.
    mutating func noteMindfulSessionBoundary(active: Bool, source: String?, at now: Date = Date()) {
        if active {
            if openMindfulStart == nil {
                openMindfulStart = now
                openMindfulSource = source
            }
        } else if let start = openMindfulStart {
            if now.timeIntervalSince(start) >= minimumMindfulDuration {
                pendingMindful.append(
                    MindfulInterval(start: start, end: now, source: openMindfulSource ?? "Composure")
                )
            }
            openMindfulStart = nil
            openMindfulSource = nil
        }
    }

    // MARK: - Flushing

    /// Returns a batch if the flush interval has elapsed (or `force` is
    /// set) and there's anything to send, `nil` otherwise. Only clears
    /// the pending buffers when it actually returns a batch.
    mutating func flushIfDue(now: Date = Date(), force: Bool = false) -> HealthSyncBatch? {
        guard force || now.timeIntervalSince(lastFlushAt) >= flushInterval else { return nil }
        lastFlushAt = now

        guard !pendingHeartRate.isEmpty || !pendingRespiratory.isEmpty || !pendingMindful.isEmpty else {
            return nil
        }

        let batch = HealthSyncBatch(
            id: UUID(),
            createdAt: now,
            heartRateSamples: pendingHeartRate,
            respiratoryRateSamples: pendingRespiratory,
            mindfulIntervals: pendingMindful
        )

        pendingHeartRate.removeAll()
        pendingRespiratory.removeAll()
        pendingMindful.removeAll()

        return batch
    }

    var pendingCount: Int {
        pendingHeartRate.count + pendingRespiratory.count + pendingMindful.count
            + (openMindfulStart != nil ? 1 : 0)
    }

    // MARK: - Private

    private func shouldRecord(_ last: Date?, now: Date) -> Bool {
        guard let last else { return true }
        return now.timeIntervalSince(last) >= minimumSampleInterval
    }
}
