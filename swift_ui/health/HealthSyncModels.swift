import Foundation

// MARK: - Samples

/// One heart rate reading. Mirrors the shape of an `HKQuantitySample`
/// closely enough that constructing one from this on a HealthKit-capable
/// platform is a direct field-for-field mapping.
struct HeartRateSample: Codable, Sendable, Equatable {
    let bpm: Double
    let timestamp: Date
}

struct RespiratoryRateSample: Codable, Sendable, Equatable {
    let breathsPerMinute: Double
    let timestamp: Date
}

/// One mindful-practice interval — the span of an active breathing or
/// meditation session, matching HealthKit's own `HKCategoryValue`
/// interval-sample shape for `mindfulSession` (start and end only, no
/// numeric value).
///
/// `source` is metadata for *this export file only* — HealthKit's own
/// mindful-session sample doesn't carry a free-text source field, so a
/// real importer would drop it or fold it into `HKMetadataKeyExternalUUID`
/// / a custom metadata key rather than the sample itself.
struct MindfulInterval: Codable, Sendable, Equatable {
    let start: Date
    let end: Date
    let source: String
}

// MARK: - Batch

/// One export unit: everything buffered since the last flush.
struct HealthSyncBatch: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let createdAt: Date
    let heartRateSamples: [HeartRateSample]
    let respiratoryRateSamples: [RespiratoryRateSample]
    let mindfulIntervals: [MindfulInterval]

    var isEmpty: Bool {
        heartRateSamples.isEmpty && respiratoryRateSamples.isEmpty && mindfulIntervals.isEmpty
    }

    var totalSampleCount: Int {
        heartRateSamples.count + respiratoryRateSamples.count + mindfulIntervals.count
    }
}
