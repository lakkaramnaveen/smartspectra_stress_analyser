import Foundation

// MARK: - Session Snapshot

/// A single point-in-time capture of the user's biometric state.
///
/// Snapshots are the atomic unit of a recorded session — cheap enough to
/// store at ~1Hz for an entire session without ballooning file size, but
/// rich enough to fully reconstruct "what was happening" at any moment
/// during replay.
struct SessionSnapshot: Codable, Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let stressScore: Double
    let heartRate: Double
    let breathingRate: Double
    let eda: Double
    let emotionalState: String
    let gazeConfidence: Double

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        stressScore: Double,
        heartRate: Double,
        breathingRate: Double,
        eda: Double,
        emotionalState: String,
        gazeConfidence: Double
    ) {
        self.id = id
        self.timestamp = timestamp
        self.stressScore = stressScore
        self.heartRate = heartRate
        self.breathingRate = breathingRate
        self.eda = eda
        self.emotionalState = emotionalState
        self.gazeConfidence = gazeConfidence
    }
}

// MARK: - Session Recording

/// A complete recorded session: metadata plus every snapshot captured
/// between `start()` and `stop()`.
struct SessionRecording: Codable, Identifiable, Equatable {
    let id: UUID
    let startedAt: Date
    var endedAt: Date?
    let difficulty: String
    var snapshots: [SessionSnapshot]

    init(
        id: UUID = UUID(),
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        difficulty: String,
        snapshots: [SessionSnapshot] = []
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.difficulty = difficulty
        self.snapshots = snapshots
    }

    var duration: TimeInterval {
        (endedAt ?? Date()).timeIntervalSince(startedAt)
    }

    var averageStress: Double { snapshots.map(\.stressScore).average }
    var peakStress: Double { snapshots.map(\.stressScore).max() ?? 0 }
    var minStress: Double { snapshots.map(\.stressScore).min() ?? 0 }
    var averageHeartRate: Double { snapshots.map(\.heartRate).average }
    var averageBreathingRate: Double { snapshots.map(\.breathingRate).average }

    /// A lightweight, metadata-only projection used for list views, so a
    /// history screen with hundreds of sessions doesn't need to
    /// deserialize every snapshot array just to render rows.
    var summary: SessionSummary {
        SessionSummary(
            id: id,
            startedAt: startedAt,
            endedAt: endedAt,
            difficulty: difficulty,
            snapshotCount: snapshots.count,
            averageStress: averageStress,
            peakStress: peakStress
        )
    }
}

// MARK: - Session Summary

/// Metadata-only view of a `SessionRecording`. Cheap to keep hundreds of
/// these in memory for a history list; the full snapshot array is only
/// loaded on demand when the user opens a specific session for replay.
struct SessionSummary: Codable, Identifiable, Equatable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date?
    let difficulty: String
    let snapshotCount: Int
    let averageStress: Double
    let peakStress: Double

    var duration: TimeInterval {
        (endedAt ?? startedAt).timeIntervalSince(startedAt)
    }
}

// MARK: - Helpers

extension Array where Element == Double {
    var average: Double {
        isEmpty ? 0 : reduce(0, +) / Double(count)
    }
}
