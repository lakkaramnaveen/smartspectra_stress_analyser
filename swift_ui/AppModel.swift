import AppKit
import Combine
import SwiftUI

/// Root view model for the Composure workspace.
///
/// Design note: this used to be a single ~400-line class that mixed SDK
/// delegate handling, stress math, emotion classification, eye-tracking
/// state, game state, and session bookkeeping. That made every change
/// risky — touching the game logic could silently affect stress
/// calculation thread-safety, for example.
///
/// It's now a thin coordinator: parsing/formatting and orchestration live
/// here, but the actual stress math lives in `StressScoringEngine` (pure,
/// testable), SDK interop lives in `BiometricEngine` (mockable), the
/// credential lives in `CredentialStoring` (secure, mockable), and session
/// history lives in `SessionRecorder` (persisted, mockable). This class's
/// job is just to wire those together and publish state for SwiftUI.
@MainActor
final class AppModel: ObservableObject {

    // MARK: - Published UI State

    @Published private(set) var frame: NSImage?
    @Published private(set) var vitalsDisplay = VitalsDisplay()
    @Published private(set) var hasLiveMetrics = false
    @Published private(set) var processingStatus = "not started"
    @Published private(set) var validationStatus = "waiting"
    @Published private(set) var errorMessage: String = ""
    @Published private(set) var diagnostics = "Frames: 0 | accepted: 0 | blocked: 0"
    @Published private(set) var isRunning = false

    @Published var apiKeyInput: String = ""

    // Personal baseline calibration
    @Published private(set) var baseline: StressBaseline?
    @Published private(set) var isCalibrating = false
    @Published private(set) var calibrationProgress: Double = 0

    // Stress & emotion
    @Published private(set) var stressScore: Double = 0.0
    @Published private(set) var stressLevel: StressLevel = .calm
    @Published private(set) var stressHistory: [Double] = []
    @Published private(set) var emotionalState: EmotionalState = .calm
    @Published private(set) var emotionIntensity: Double = 0.0
    @Published var isBiofeedbackActive = false

    // Eye tracking
    @Published private(set) var gaze: GazePoint = .center
    @Published private(set) var blinkDetected = false
    @Published var isEyeTrackingAvailable = true

    // Game
    @Published private(set) var gameStats = GameSessionStats()
    @Published var gameDifficulty: GameDifficulty = .medium
    @Published private(set) var isGameActive = false

    // Session
    @Published private(set) var sessionStats = SessionStats()

    // MARK: - Trace History (for sparkline charts)

    var pulseTraceHistory: [Double] { pulseTrace.elements.isEmpty ? pulseTrendHistory.elements : pulseTrace.elements }
    var breathingTraceHistory: [Double] { breathingTrace.elements }
    var edaTraceHistory: [Double] { edaTrace.elements }

    // MARK: - Dependencies (injected — see init)

    private let engine: BiometricEngineProviding
    private let credentialStore: CredentialStoring
    private var scoringEngine: StressScoringEngine
    private let sessionRecorder: SessionRecorder   // ← was missing as a stored property
    let prediction: StressPredictionCoordinator     // not private: views read it
    private let baselineStore: BaselineStoring
    private var calibrator = BaselineCalibrator()
    private var calibrationTimerTask: Task<Void, Never>?

    // MARK: - Internal buffers / state not exposed directly to views

    private var pulseTrace = RollingBuffer<Double>(capacity: 80)
    private var breathingTrace = RollingBuffer<Double>(capacity: 80)
    private var edaTrace = RollingBuffer<Double>(capacity: 1024)
    private var pulseTrendHistory = RollingBuffer<Double>(capacity: 80)
    private var stressBuffer = RollingBuffer<Double>(capacity: 300) // 5 min @ 1 Hz

    private var latestPulse: Double = 0
    private var latestBreathing: Double = 0
    private var latestEDA: Double = 0

    private var sessionTimerTask: Task<Void, Never>?
    private var gameTimerTask: Task<Void, Never>?
    private var blinkResetTask: Task<Void, Never>?
    private var biofeedbackResetTask: Task<Void, Never>?

    // MARK: - Init

    /// `sessionRecorder` defaults to `nil` here (not `SessionRecorder()`)
    /// deliberately: default-argument *expressions* are evaluated in a
    /// non-isolated context even when the initializer they belong to is
    /// `@MainActor`, and `SessionRecorder.init` is itself MainActor-isolated
    /// (it's an `ObservableObject` meant to publish to SwiftUI). Passing
    /// `nil` sidesteps that — the real instance is constructed inside the
    /// init body below, which *does* run on the main actor.
    init(
        engine: BiometricEngineProviding = BiometricEngine(),
        credentialStore: CredentialStoring = KeychainCredentialStore(),
        scoringEngine: StressScoringEngine = StressScoringEngine(),
        sessionRecorder: SessionRecorder? = nil,
        prediction: StressPredictionCoordinator? = nil,
        baselineStore: BaselineStoring? = nil
    ) {
        self.engine = engine
        self.credentialStore = credentialStore
        self.scoringEngine = scoringEngine
        self.sessionRecorder = sessionRecorder ?? SessionRecorder()
        self.prediction = prediction ?? StressPredictionCoordinator()
        self.baselineStore = baselineStore ?? BaselineStore()

        // Pre-fill the input field from Keychain so returning users don't
        // have to re-enter their key every launch — but never store it
        // anywhere insecure ourselves.
        self.apiKeyInput = credentialStore.loadAPIKey() ?? ""

        // If a baseline was already captured in a previous launch,
        // personalize scoring from the start rather than waiting for the
        // user to recalibrate every session.
        if let savedBaseline = self.baselineStore.load() {
            self.baseline = savedBaseline
            self.scoringEngine = .init(config: .personalized(from: savedBaseline))
        }

        if let engine = engine as? BiometricEngine {
            engine.delegate = self
        }
    }

    deinit {
        sessionTimerTask?.cancel()
        gameTimerTask?.cancel()
        blinkResetTask?.cancel()
        biofeedbackResetTask?.cancel()
        calibrationTimerTask?.cancel()
    }

    // MARK: - Lifecycle Controls

    func start() {
        resetSessionState()

        let trimmedKey = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            try credentialStore.save(apiKey: trimmedKey)
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        if let engineError = engine.start(apiKey: trimmedKey) {
            errorMessage = engineError.localizedDescription
            isRunning = false
            return
        }

        errorMessage = ""
        isRunning = true
        startSessionTimer()
        sessionRecorder.start(difficulty: gameDifficulty.label)
    }

    func stop() {
        engine.stop()
        isRunning = false
        processingStatus = "stopped"
        isBiofeedbackActive = false
        stopGame()
        stopSessionTimer()
        sessionRecorder.stop()
        if isCalibrating { cancelCalibration() }
    }

    // MARK: - Game Controls

    func startGame(difficulty: GameDifficulty? = nil) {
        if let difficulty { gameDifficulty = difficulty }
        gameStats = GameSessionStats()
        isGameActive = true
        startGameTimer()
    }

    func stopGame() {
        isGameActive = false
        gameTimerTask?.cancel()
    }

    func recordBalloonPop() {
        let points = Int(10 * gameDifficulty.pointMultiplier)
        gameStats.score += points
        gameStats.balloonsPopped += 1
    }

    // MARK: - Eye Tracking

    func updateGaze(x: Double, y: Double, confidence: Double) {
        gaze = GazePoint(
            x: x.clamped(to: 0...1),
            y: y.clamped(to: 0...1),
            confidence: confidence.clamped(to: 0...1)
        )
    }

    func registerBlink() {
        blinkResetTask?.cancel()
        blinkDetected = true
        blinkResetTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            self?.blinkDetected = false
        }
    }

    func dismissBiofeedback() {
        biofeedbackResetTask?.cancel()
        isBiofeedbackActive = false
    }

    /// Starts a breathing intervention on the user's own initiative (e.g.
    /// tapping "Start breathing" on a predictive alert), as opposed to
    /// `triggerBiofeedback()` which fires automatically at the threshold.
    func beginBreathingManually() {
        prediction.dismissAlert()
        triggerBiofeedback()
    }

    // MARK: - Baseline Calibration

    /// Begins a ~60s "sit still and breathe normally" calibration run.
    /// Requires a live session (camera + SDK already running) — while
    /// calibrating, incoming vitals feed the calibrator instead of the
    /// normal stress-scoring path (see `recomputeDerivedState`), so
    /// scoring against not-yet-personalized thresholds doesn't flash a
    /// misleading score or trigger a breathing intervention mid-run.
    func startCalibration() {
        guard isRunning, !isCalibrating else { return }

        calibrator = BaselineCalibrator()
        calibrator.start()
        isCalibrating = true
        calibrationProgress = 0

        calibrationTimerTask?.cancel()
        calibrationTimerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled, let self else { return }
                self.calibrationProgress = self.calibrator.progress
                if self.calibrator.isComplete {
                    self.finishCalibration()
                    return
                }
            }
        }
    }

    func cancelCalibration() {
        calibrationTimerTask?.cancel()
        calibrationTimerTask = nil
        isCalibrating = false
        calibrationProgress = 0
    }

    /// Discards the saved baseline and reverts to population-default
    /// thresholds. Exposed so a bad calibration (e.g. run while
    /// distracted) can be undone without reinstalling the app.
    func resetBaseline() {
        baseline = nil
        scoringEngine = StressScoringEngine()
        baselineStore.clear()
    }

    private func finishCalibration() {
        calibrationTimerTask?.cancel()
        calibrationTimerTask = nil
        isCalibrating = false

        guard let newBaseline = calibrator.finish() else {
            errorMessage = "Calibration needs more data — make sure your face stays visible and try again."
            calibrationProgress = 0
            return
        }

        baseline = newBaseline
        scoringEngine = StressScoringEngine(config: .personalized(from: newBaseline))
        calibrationProgress = 1.0

        do {
            try baselineStore.save(newBaseline)
        } catch {
            errorMessage = "Baseline captured but couldn't be saved: \(error.localizedDescription)"
        }
    }

    // MARK: - Private: Session Lifecycle

    private func resetSessionState() {
        if isCalibrating { cancelCalibration() }
        errorMessage = ""
        vitalsDisplay = VitalsDisplay()
        hasLiveMetrics = false
        diagnostics = "Frames: 0 | accepted: 0 | blocked: 0"

        pulseTrace.removeAll()
        breathingTrace.removeAll()
        edaTrace.removeAll()
        pulseTrendHistory.removeAll()
        stressBuffer.removeAll()

        latestPulse = 0
        latestBreathing = 0
        latestEDA = 0

        isBiofeedbackActive = false
        stressScore = 0
        stressLevel = .calm
        stressHistory = []
        emotionalState = .calm
        emotionIntensity = 0
        prediction.reset()

        sessionStats = SessionStats(startedAt: Date())
    }

    private func startSessionTimer() {
        sessionTimerTask?.cancel()
        sessionTimerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self?.sessionStats.elapsedSeconds += 1
            }
        }
    }

    private func stopSessionTimer() {
        sessionTimerTask?.cancel()
        sessionTimerTask = nil
    }

    private func startGameTimer() {
        gameTimerTask?.cancel()
        gameTimerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                guard !Task.isCancelled else { return }
                self?.gameStats.elapsedSeconds += 0.016
            }
        }
    }

    // MARK: - Private: Vitals Parsing

    /// Parses lines like "Pulse rate: 72.0 (0.91)" from the SDK's metrics
    /// array into numeric value + confidence string.
    private func parseRate(_ line: String) -> (value: Double, confidence: String?)? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let remainder = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        guard let firstToken = remainder.split(separator: " ").first,
              let value = Double(firstToken) else { return nil }

        var confidence: String?
        if let open = line.lastIndex(of: "("), let close = line.lastIndex(of: ")"), open < close {
            confidence = String(line[line.index(after: open)..<close])
        }
        return (value, confidence)
    }

    private func applyMetrics(_ metrics: [String]) {
        let tilePrefixes = ["Pulse rate:", "Breathing rate:", "EDA level:"]

        for line in metrics {
            if line.hasPrefix("Pulse rate:"), let parsed = parseRate(line) {
                vitalsDisplay.pulseBPM = formattedInt(parsed.value)
                vitalsDisplay.pulseConfidence = parsed.confidence ?? ""
                pulseTrendHistory.append(parsed.value)
                latestPulse = parsed.value
                recomputeDerivedState()
            } else if line.hasPrefix("Breathing rate:"), let parsed = parseRate(line) {
                vitalsDisplay.breathingRPM = formattedInt(parsed.value)
                vitalsDisplay.breathingConfidence = parsed.confidence ?? ""
                latestBreathing = parsed.value
                recomputeDerivedState()
            } else if line.hasPrefix("EDA level:"), let parsed = parseRate(line) {
                vitalsDisplay.edaLevel = formattedEDA(parsed.value)
                latestEDA = parsed.value
                recomputeDerivedState()
            }
        }

        vitalsDisplay.otherMetrics = metrics.filter { line in
            !tilePrefixes.contains(where: line.hasPrefix)
        }
    }

    private func applyTraces(breathing: [Double], arterialPressure: [Double], eda: [Double]) {
        breathingTrace.append(contentsOf: breathing)
        pulseTrace.append(contentsOf: arterialPressure)
        edaTrace.append(contentsOf: eda)

        if let latest = eda.last {
            vitalsDisplay.edaLevel = formattedEDA(latest)
            latestEDA = latest
            recomputeDerivedState()
        }

        if !breathing.isEmpty || !arterialPressure.isEmpty || !eda.isEmpty {
            hasLiveMetrics = true
        }
    }

    private func formattedInt(_ value: Double) -> String {
        "\(Int(value.rounded()))"
    }

    private func formattedEDA(_ value: Double) -> String {
        String(format: "%+.3f", value)
    }

    // MARK: - Private: Stress & Emotion

    private func recomputeDerivedState() {
        if isCalibrating {
            calibrator.ingest(pulseBPM: latestPulse, eda: latestEDA, breathingRPM: latestBreathing)
            return
        }

        guard let score = scoringEngine.stressScore(eda: latestEDA, breathingRPM: latestBreathing) else {
            return
        }

        stressScore = score
        stressLevel = StressLevel.classify(score)
        recordStressSample(score)

        let (state, intensity) = scoringEngine.emotionalState(
            pulseBPM: latestPulse,
            eda: latestEDA,
            breathingRPM: latestBreathing
        )
        emotionalState = state
        emotionIntensity = intensity

        sessionRecorder.capture(
            stressScore: score,
            heartRate: latestPulse,
            breathingRate: latestBreathing,
            eda: latestEDA,
            emotionalState: state.label,
            gazeConfidence: gaze.confidence
        )

        prediction.ingest(score: score, interventionActive: isBiofeedbackActive)

        if scoringEngine.shouldTriggerIntervention(forStressScore: score), !isBiofeedbackActive {
            triggerBiofeedback()
        }
    }

    private func recordStressSample(_ value: Double) {
        stressBuffer.append(value)
        stressHistory = stressBuffer.elements

        sessionStats.peakStress = max(sessionStats.peakStress, value)
        if !stressBuffer.elements.isEmpty {
            sessionStats.averageStress = stressBuffer.elements.reduce(0, +) / Double(stressBuffer.elements.count)
        }
    }

    private func triggerBiofeedback() {
        isBiofeedbackActive = true
        biofeedbackResetTask?.cancel()
        biofeedbackResetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled else { return }
            self?.isBiofeedbackActive = false
        }
    }
}

// MARK: - BiometricEngineDelegate

extension AppModel: BiometricEngineDelegate {
    nonisolated func biometricEngine(_ engine: BiometricEngine, didCaptureFrame image: NSImage) {
        Task { @MainActor in self.frame = image }
    }

    nonisolated func biometricEngine(
        _ engine: BiometricEngine,
        didUpdateProcessingStatus processing: String,
        validationStatus: String
    ) {
        Task { @MainActor in
            if !processing.isEmpty { self.processingStatus = processing }
            if !validationStatus.isEmpty { self.validationStatus = validationStatus }
        }
    }

    nonisolated func biometricEngine(
        _ engine: BiometricEngine,
        didUpdateMetrics metrics: [String],
        timestampMicros: Int64
    ) {
        guard !metrics.isEmpty else { return }
        Task { @MainActor in
            self.applyMetrics(metrics)
            self.hasLiveMetrics = true
        }
    }

    nonisolated func biometricEngine(
        _ engine: BiometricEngine,
        didUpdateTraces breathing: [Double],
        arterialPressure: [Double],
        eda: [Double],
        timestampMicros: Int64
    ) {
        Task { @MainActor in
            self.applyTraces(breathing: breathing, arterialPressure: arterialPressure, eda: eda)
        }
    }

    nonisolated func biometricEngine(_ engine: BiometricEngine, didUpdateDiagnostics diagnostics: String) {
        Task { @MainActor in self.diagnostics = diagnostics }
    }

    nonisolated func biometricEngine(_ engine: BiometricEngine, didFailWith error: BiometricEngineError) {
        Task { @MainActor in
            self.errorMessage = error.localizedDescription
            if self.isRunning { self.stop() }
            self.processingStatus = "failed"
        }
    }
}

// MARK: - Supporting Types

/// Display-ready vitals strings, separated from raw numeric state so the
/// formatting logic ("--" placeholders, confidence strings) lives in one
/// place instead of being recomputed in every view that shows a vital.
struct VitalsDisplay: Equatable {
    var pulseBPM: String = "--"
    var pulseConfidence: String = ""
    var breathingRPM: String = "--"
    var breathingConfidence: String = ""
    var edaLevel: String = "--"
    var otherMetrics: [String] = ["Waiting for metrics..."]
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
