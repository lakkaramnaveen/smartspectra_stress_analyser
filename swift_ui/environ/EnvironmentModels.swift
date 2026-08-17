import Foundation

// MARK: - Dimension

enum EnvironmentDimension: String, Sendable, CaseIterable {
    case lighting
    case noise

    var label: String {
        switch self {
        case .lighting: return "Lighting"
        case .noise: return "Noise"
        }
    }

    var icon: String {
        switch self {
        case .lighting: return "light.max"
        case .noise: return "waveform"
        }
    }
}

// MARK: - Samples

/// One brightness reading, derived from a camera frame already being
/// captured for the core biometric feature — no new data collection, no
/// new permission. See `LightingAnalyzer`.
struct BrightnessSample: Codable, Equatable, Sendable {
    let timestamp: Date
    /// 0 (black) ... 1 (white).
    let value: Double
}

/// One ambient noise reading — a single normalized level, never audio.
/// See the design note on `NoiseLevelMonitor` for exactly what this is
/// and isn't.
struct NoiseSample: Codable, Equatable, Sendable {
    let timestamp: Date
    /// 0 (silent) ... 1 (loud), a heuristic scaling — not a calibrated
    /// decibel measurement.
    let value: Double
}

// MARK: - Persisted State

struct EnvironmentState: Codable, Equatable, Sendable {
    var brightnessSamples: [BrightnessSample]
    var noiseSamples: [NoiseSample]
    /// Lighting analysis needs no toggle — it's additional analysis of
    /// camera frames the app is already capturing for its core purpose,
    /// nothing new is being observed. Noise is different: it requires a
    /// new permission and a new sensor, off by default like every other
    /// opt-in data source in this app.
    var noiseMonitoringEnabled: Bool

    static let initial = EnvironmentState(brightnessSamples: [], noiseSamples: [], noiseMonitoringEnabled: false)
}

// MARK: - Association

/// A tercile comparison — mean stress during this dimension's calmest
/// third of readings versus its most extreme third — the same shape
/// `SleepStressAnalyzer` uses for "stress after your most vs. least
/// restful nights." Reused here rather than inventing a second way to
/// say the same kind of thing.
struct EnvironmentAssociation: Sendable {
    let dimension: EnvironmentDimension
    let sampleCount: Int
    let stressInLowerThird: Double
    let stressInUpperThird: Double
    let coefficient: Double?
}
