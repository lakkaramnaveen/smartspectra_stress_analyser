import Foundation

/// Reconciles the camera's own heart-rate average against whatever
/// wearable readings overlap a session.
///
/// Pure and UI-free — same shape as `RecoveryDetector` and
/// `SleepStressAnalyzer`. This is deliberately a **retrospective,
/// after-the-fact comparison**, not live sensor fusion. Nothing in this
/// app receives wearable data in real time — Oura syncs on its own
/// schedule and samples heart rate at five-minute increments even when
/// it does, and an imported Watch file is, by definition, historical.
/// A live per-sample Kalman-style blend would imply a synchrony between
/// sources that doesn't exist; what's actually true, and what this
/// computes, is "how did this session's camera average compare to
/// whatever the wearables recorded around the same time."
struct BiometricFusionEngine: Sendable {

    /// Deviation, in bpm, within which camera and wearable are treated
    /// as agreeing rather than conflicting.
    let concordantToleranceBPM: Double

    init(concordantToleranceBPM: Double = 8) {
        self.concordantToleranceBPM = concordantToleranceBPM
    }

    /// How much to trust the camera's own average for this session.
    ///
    /// Not the SDK's own per-instant confidence value — that reflects
    /// one moment, not the session as a whole. Instead this is derived
    /// from the session's own statistics: more samples, and lower
    /// relative spread between them, both point toward a number worth
    /// trusting. This is a heuristic, stated as one — it isn't a
    /// calibrated instrument, just a reasonable way to avoid treating a
    /// four-sample, wildly-varying "average" as equally trustworthy to a
    /// two-hundred-sample stable one.
    func cameraConfidence(for summary: CameraHeartRateSummary) -> Double {
        let sampleFactor = min(Double(summary.sampleCount) / 60.0, 1.0)

        let coefficientOfVariation = summary.averageBPM > 0
            ? summary.standardDeviationBPM / summary.averageBPM
            : 1.0
        // A coefficient of variation above ~25% for a resting-ish heart
        // rate reading is high enough that "average" is doing a lot of
        // work smoothing over real instability in the signal.
        let stabilityFactor = max(0, 1 - (coefficientOfVariation / 0.25))

        return (sampleFactor * 0.5) + (stabilityFactor * 0.5)
    }

    /// Produces the reconciliation for one session.
    func reconcile(
        camera: CameraHeartRateSummary,
        wearableReadings: [WearableReading]
    ) -> SessionReconciliation {
        guard !wearableReadings.isEmpty else {
            return SessionReconciliation(
                cameraAverageBPM: camera.averageBPM,
                cameraSampleCount: camera.sampleCount,
                wearableReadings: [],
                blendedEstimateBPM: nil,
                agreement: .noWearableData,
                maxDeviationBPM: nil
            )
        }

        let cameraConf = cameraConfidence(for: camera)

        var weightedSum = camera.averageBPM * cameraConf
        var weightTotal = cameraConf
        var maxDeviation: Double = 0

        for reading in wearableReadings {
            weightedSum += reading.bpm * reading.confidence
            weightTotal += reading.confidence
            maxDeviation = max(maxDeviation, abs(reading.bpm - camera.averageBPM))
        }

        let blended = weightTotal > 0 ? weightedSum / weightTotal : nil
        let agreement: AgreementLevel = maxDeviation <= concordantToleranceBPM ? .concordant : .divergent

        return SessionReconciliation(
            cameraAverageBPM: camera.averageBPM,
            cameraSampleCount: camera.sampleCount,
            wearableReadings: wearableReadings,
            blendedEstimateBPM: blended,
            agreement: agreement,
            maxDeviationBPM: maxDeviation
        )
    }
}
