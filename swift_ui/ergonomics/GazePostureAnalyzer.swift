import Foundation

/// Tracks vertical gaze position against a session baseline.
///
/// Pure and UI-free — same shape as `StressScoringEngine` and
/// `CorrelationAnalyzer`, so the behaviour can be tested with plain
/// input/output assertions.
///
/// **What this measures, precisely:** the vertical position of the
/// user's gaze within the camera frame, relative to where it sat during
/// the first 30 confident samples of the session. That's a usable proxy
/// for "looking down at a keyboard, phone, or notes" and for gradual
/// slumping toward the desk.
///
/// **What it does not measure:** spinal posture. Gaze direction and back
/// position are only loosely coupled, and camera height determines the
/// mapping between them — a laptop camera below eye level and an
/// external webcam above it give opposite readings for identical
/// posture. Nothing in this type should be used to tell a user their
/// posture is wrong.
struct GazePostureAnalyzer {

    let config: ErgonomicsConfig

    private var baselineSamples: [Double] = []
    private(set) var baseline: GazeBaseline?

    /// Start of the current unbroken downward stretch, if any.
    private var downwardStreakStart: Date?

    init(config: ErgonomicsConfig = .default) {
        self.config = config
    }

    // MARK: - Result

    struct Reading: Equatable {
        let quality: GazeSignalQuality
        let drift: Double?
        let isLookingDown: Bool
        /// Duration of the current unbroken downward stretch.
        let currentDownwardStreak: TimeInterval
        /// Seconds to add to cumulative downward time for this tick.
        let downwardIncrement: TimeInterval
    }

    // MARK: - Ingestion

    /// Feed a gaze sample.
    ///
    /// - Parameters:
    ///   - verticalPosition: normalised 0...1, where larger is lower in
    ///     the frame (matching `GazePoint.y`).
    ///   - confidence: tracker confidence, 0...1.
    ///   - interval: seconds since the previous sample.
    mutating func ingest(
        verticalPosition: Double,
        confidence: Double,
        interval: TimeInterval,
        now: Date = Date()
    ) -> Reading {
        let quality = GazeSignalQuality.classify(confidence)

        // An unusable sample must not accumulate time. If the tracker
        // has lost the face, "looking down" is unknowable, and counting
        // that interval as downward would let a user who stepped away
        // return to a confident, entirely fabricated statistic.
        guard quality != .unusable else {
            downwardStreakStart = nil
            return Reading(
                quality: .unusable,
                drift: nil,
                isLookingDown: false,
                currentDownwardStreak: 0,
                downwardIncrement: 0
            )
        }

        // Establish the baseline before making any relative claims.
        guard let baseline else {
            captureBaselineSample(verticalPosition, now: now)
            return Reading(
                quality: quality,
                drift: nil,
                isLookingDown: false,
                currentDownwardStreak: 0,
                downwardIncrement: 0
            )
        }

        let drift = verticalPosition - baseline.verticalCentre
        let isDown = drift >= config.downwardThreshold

        var streak: TimeInterval = 0
        var increment: TimeInterval = 0

        if isDown {
            if downwardStreakStart == nil { downwardStreakStart = now }
            streak = downwardStreakStart.map { now.timeIntervalSince($0) } ?? 0
            increment = interval
        } else {
            downwardStreakStart = nil
        }

        return Reading(
            quality: quality,
            drift: drift,
            isLookingDown: isDown,
            currentDownwardStreak: streak,
            downwardIncrement: increment
        )
    }

    /// Re-anchor the baseline to the current position.
    ///
    /// Exposed as a user action ("I've adjusted my setup") because a
    /// baseline captured before someone raised their monitor or swapped
    /// chairs is worse than no baseline — it would report a permanent
    /// drift that reflects furniture, not the person.
    mutating func recalibrate() {
        baseline = nil
        baselineSamples.removeAll()
        downwardStreakStart = nil
    }

    mutating func reset() {
        recalibrate()
    }

    // MARK: - Private

    private mutating func captureBaselineSample(_ value: Double, now: Date) {
        baselineSamples.append(value)

        guard baselineSamples.count >= GazeBaseline.requiredSamples else { return }

        // Median rather than mean: a few frames where the user glanced
        // at their phone shouldn't drag the reference point downward for
        // the whole session.
        let sorted = baselineSamples.sorted()
        let median = sorted[sorted.count / 2]

        baseline = GazeBaseline(
            verticalCentre: median,
            capturedAt: now,
            sampleCount: baselineSamples.count
        )
    }
}
