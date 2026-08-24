import Foundation
import SwiftUI

// MARK: - Signal Quality

/// How trustworthy the current beat-interval stream is.
///
/// Every downstream claim is gated on this. Camera-derived
/// photoplethysmography degrades sharply with movement, lighting changes,
/// and partial face occlusion, and a variability figure computed from a
/// corrupted interval series looks exactly as authoritative as a good
/// one. Refusing to report is the only honest option when the input is
/// bad.
enum BeatSignalQuality: Equatable, Sendable {
    case good
    case marginal
    case unusable

    var label: String {
        switch self {
        case .good: return "Good signal"
        case .marginal: return "Noisy signal"
        case .unusable: return "Signal too noisy to measure"
        }
    }

    var color: Color {
        switch self {
        case .good: return BrandColor.mint
        case .marginal: return BrandColor.amber
        case .unusable: return BrandColor.mediumGray
        }
    }
}

// MARK: - Beat Interval

/// One inter-beat interval, in milliseconds.
struct BeatInterval: Equatable, Sendable {
    let milliseconds: Double
    let timestamp: Date

    /// Physiologically plausible range, ~30–200 bpm. Anything outside is
    /// a detection artefact — a missed beat produces a doubled interval,
    /// a spurious peak produces a halved one — and admitting either would
    /// inflate variability enormously.
    static let plausibleRange: ClosedRange<Double> = 300...2000
}

// MARK: - Measurement

/// A variability measurement over one window of beats.
struct HRVMeasurement: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let timestamp: Date

    /// Root mean square of successive differences, in milliseconds.
    ///
    /// Named for what it is, but see `HRVReading.disclaimer` for why it's
    /// never shown against population norms.
    let rmssd: Double

    /// Standard deviation of intervals, in milliseconds.
    let sdnn: Double

    /// Mean heart rate over the window.
    let meanBPM: Double

    /// Beats the window was computed from.
    let beatCount: Int

    /// Proportion of candidate intervals rejected as artefacts. High
    /// values mean the figure rests on heavily filtered data.
    let artefactRate: Double

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        rmssd: Double,
        sdnn: Double,
        meanBPM: Double,
        beatCount: Int,
        artefactRate: Double
    ) {
        self.id = id
        self.timestamp = timestamp
        self.rmssd = rmssd
        self.sdnn = sdnn
        self.meanBPM = meanBPM
        self.beatCount = beatCount
        self.artefactRate = artefactRate
    }
}

// MARK: - Personal Band

/// Where a measurement sits relative to *this user's* recent history.
///
/// Deliberately not "recovery / baseline / stressed" with fixed
/// millisecond cutoffs. Resting RMSSD varies by an order of magnitude
/// between healthy people — age, fitness, and genetics dominate — so
/// absolute bands would tell most users something false about
/// themselves. Comparison against their own rolling baseline is the only
/// framing this data supports.
enum HRVBand: Equatable, Sendable {
    case belowUsual
    case aroundUsual
    case aboveUsual
    /// Not enough personal history to compare against yet.
    case establishing

    var label: String {
        switch self {
        case .belowUsual: return "Below your usual"
        case .aroundUsual: return "Around your usual"
        case .aboveUsual: return "Above your usual"
        case .establishing: return "Still learning your usual"
        }
    }

    var color: Color {
        switch self {
        case .belowUsual: return BrandColor.amber
        case .aroundUsual: return BrandColor.lightBlue
        case .aboveUsual: return BrandColor.mint
        case .establishing: return BrandColor.mediumGray
        }
    }

    /// Interpretation, kept modest.
    ///
    /// Higher short-term variability is broadly associated with
    /// parasympathetic ("rest and digest") activity, and lower with
    /// sympathetic activation — but that association is a population
    /// tendency, not a readout, and a single window says very little.
    /// The copy reflects that.
    var note: String {
        switch self {
        case .belowUsual:
            return "Lower variability than you've been running lately. That often accompanies exertion, poor sleep, or stress — though a single reading doesn't tell you which."
        case .aroundUsual:
            return "In line with your recent readings."
        case .aboveUsual:
            return "Higher variability than your recent average, which tends to go with a more rested state."
        case .establishing:
            return "A few more sessions and there'll be enough history to compare against."
        }
    }
}

// MARK: - Reading

/// A measurement paired with its personal context — what the UI shows.
struct HRVReading: Equatable, Sendable {
    let measurement: HRVMeasurement
    let band: HRVBand
    let personalBaseline: Double?
    let quality: BeatSignalQuality

    /// Percentage difference from the user's rolling baseline.
    var percentFromBaseline: Double? {
        guard let personalBaseline, personalBaseline > 0 else { return nil }
        return ((measurement.rmssd - personalBaseline) / personalBaseline) * 100
    }

    /// Shown alongside every reading, not tucked away.
    ///
    /// Two facts a reader genuinely needs: the number comes from a
    /// camera rather than an ECG, and it is not being compared to
    /// anything but their own history. Without both, an RMSSD figure
    /// invites comparison against the published ranges that turn up
    /// immediately on searching the term.
    static let disclaimer = "Measured from the camera, not an ECG or chest strap — treat it as a rough trend for yourself rather than a clinical number, and don't compare it to published ranges."
}

// MARK: - Configuration

struct HRVConfig: Sendable {
    /// Beats needed before a measurement is produced.
    ///
    /// RMSSD over fewer than ~30 beats is dominated by noise. Short
    /// windows are common in consumer apps and are largely why their
    /// readings jump around.
    var minimumBeatsPerWindow: Int = 30

    /// Beats retained for the rolling measurement window.
    var windowBeats: Int = 60

    /// Maximum share of rejected intervals before a window is discarded
    /// entirely rather than measured.
    var maximumArtefactRate: Double = 0.25

    /// Measurements needed before personal bands are offered.
    var minimumMeasurementsForBaseline: Int = 20

    /// Deviation from baseline that counts as meaningfully different.
    /// Percentage of the baseline value.
    var bandThresholdPercent: Double = 15

    /// Minimum waveform sample rate. Below this, peak timing is too
    /// coarse for the result to mean anything — see the note in
    /// `BeatDetector`.
    var minimumSampleRateHz: Double = 25

    static let `default` = HRVConfig()
}
