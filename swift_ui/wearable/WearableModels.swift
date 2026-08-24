import Foundation
import SwiftUI

// MARK: - Source

enum WearableSource: String, Codable, Equatable, Sendable {
    case oura
    case appleWatch

    var label: String {
        switch self {
        case .oura: return "Oura"
        case .appleWatch: return "Apple Watch"
        }
    }

    var icon: String {
        switch self {
        case .oura: return "circle.circle"
        case .appleWatch: return "applewatch"
        }
    }
}

// MARK: - Reading

/// One heart-rate reading from an external source, with a confidence
/// weight used when blending against the camera's own reading.
struct WearableReading: Equatable, Sendable {
    let source: WearableSource
    let bpm: Double
    let timestamp: Date
    /// 0...1. Oura's own PPG heart-rate accuracy is well-documented for
    /// resting conditions, hence a fairly high default; Apple Watch
    /// import readings get a similarly high but fixed value since there's
    /// no per-sample confidence in an imported file to draw on — both are
    /// assumptions stated here, not measured values, and are marked as
    /// such wherever they're used.
    let confidence: Double
}

// MARK: - Camera Summary

/// Statistics over one session's own camera-derived heart-rate readings.
struct CameraHeartRateSummary: Equatable, Sendable {
    let averageBPM: Double
    let sampleCount: Int
    let standardDeviationBPM: Double

    /// Builds a summary, or `nil` if there isn't enough data to say
    /// anything — same evidence-gating principle as every other analyzer
    /// in this app. Five readings is little enough that averaging them
    /// is still meaningful for pulling a single number out, but far too
    /// few to trust as a *stable* number, which is why the confidence
    /// heuristic in `BiometricFusionEngine` weighs sample count as well.
    static func from(heartRates: [Double]) -> CameraHeartRateSummary? {
        let valid = heartRates.filter { $0 > 0 }
        guard valid.count >= 5 else { return nil }

        let mean = valid.average
        let variance = valid.map { ($0 - mean) * ($0 - mean) }.average
        return CameraHeartRateSummary(
            averageBPM: mean,
            sampleCount: valid.count,
            standardDeviationBPM: variance.squareRoot()
        )
    }
}

// MARK: - Reconciliation

enum AgreementLevel: Equatable, Sendable {
    /// No wearable readings overlapped the session's time window.
    case noWearableData
    /// Camera and wearable readings landed within tolerance of each other.
    case concordant
    /// A meaningful gap — worth treating the camera reading with more
    /// caution for that session, not necessarily wrong.
    case divergent

    var label: String {
        switch self {
        case .noWearableData: return "No wearable data for this session"
        case .concordant: return "Readings agree"
        case .divergent: return "Readings diverge"
        }
    }

    var color: Color {
        switch self {
        case .noWearableData: return BrandColor.mediumGray
        case .concordant: return BrandColor.mint
        case .divergent: return BrandColor.amber
        }
    }
}

struct SessionReconciliation: Equatable, Sendable {
    let cameraAverageBPM: Double
    let cameraSampleCount: Int
    let wearableReadings: [WearableReading]
    /// Confidence-weighted blend across camera and every matched
    /// wearable reading. `nil` when there's nothing to blend against.
    let blendedEstimateBPM: Double?
    let agreement: AgreementLevel
    let maxDeviationBPM: Double?
}
