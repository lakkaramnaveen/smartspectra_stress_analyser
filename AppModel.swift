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
/// It's now a thin coordinator. Parsing, formatting, and orchestration
/// live here; everything else is a composed dependency:
///
///   - `StressScoringEngine`         — pure stress/emotion math
///   - `BiometricEngine`             — SDK interop, mockable
///   - `CredentialStoring`           — Keychain, mockable
///   - `SessionRecorder`             — session history
///   - `StressPredictionCoordinator` — trend forecasting & alerts
///   - `GoalsCoordinator`            — streaks, achievements, records
///   - `BreathingCoordinator`        — technique library & pacer state
///   - `FocusCoordinator`            — Pomodoro blocks
///   - `MeditationCoordinator`       — guided sittings
///   - `ErgonomicsCoordinator`       — screen time & neck-strain nudges
///
/// This class's job is to wire those together and publish state for
/// SwiftUI.
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

    // Stress & emotion
    @Published private(set) var stressScore: Double = 0.0
    @Published private(set) var stressLevel: StressLevel = .calm
    @Published private(set) var stressHistory: [Double] = []
    @Published private(set) var emotionalState: EmotionalState = .calm
    @Published private(set) var emotionIntensity: Double = 0.0
    @Published private(set) var isBiofeedbackActive = false

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
    private let scoringEngine: StressScoringEngine
    private let sessionRecorder: SessionRecorder

    // Exposed so views can bind to them directly. `let`, because nothing
    // should ever swap which coordinator the model points at — their
    // *contents* change, not their identity.
    let prediction: StressPredictionCoordinator
    let goals: GoalsCoordinator
    let breathing: BreathingCoordinator
    let focus: FocusCoordinator
    let meditation: MeditationCoordinator
    let ergonomics: ErgonomicsCoordinator

    /// Subscriptions forwarding child coordinators' change notifications
    /// into our own. See `forwardChildChanges()`.
    private var childObservers: Set<AnyCancellable> = []

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

    /// Every coordinator parameter defaults to `nil` rather than to a
    /// constructed instance, deliberately: default-argument *expressions*
    /// evaluate in a non-isolated context even when the initializer they
    /// belong to is `@MainActor`, and these types are all MainActor-bound
    /// `ObservableObject`s. Building them inside the init body — which
    /// does run on the main actor — sidesteps the isolation error while
    /// keeping them injectable for tests.
    init(
        engine: BiometricEngineProviding = BiometricEngine(),
        credentialStore: CredentialStoring = KeychainCredentialStore(),
        scoringEngine: StressScoringEngine = StressScoringEngine(),
        sessionRecorder: SessionRecorder? = nil,
        prediction: StressPredictionCoordinator? = nil,
        goals: GoalsCoordinator? = nil,
        breathing: BreathingCoordinator? = nil,
        focus: FocusCoordinator? = nil,
        meditation: MeditationCoordinator? = nil,
        ergonomics: ErgonomicsCoordinator? = nil
    ) {
        // ---------------------------------------------------------------
        // Phase 1 — assign EVERY stored property.
        //
        // Nothing below this block may touch `self` until all of them are
        // set: Swift forbids using `self` in an initializer until the
        // instance is fully formed. Assigning a coordinator *after*
        // something like `engine.delegate = self` is a compile error, and
        // an easy one to introduce when adding a new dependency, so
        // keeping every assignment together in one block is the simplest
        // way to make that mistake impossible.
        // ---------------------------------------------------------------
        self.engine = engine
        self.credentialStore = credentialStore
        self.scoringEngine = scoringEngine

        self.sessionRecorder = sessionRecorder ?? SessionRecorder()
        self.prediction = prediction ?? StressPredictionCoordinator()
        self.goals = goals ?? GoalsCoordinator()
        self.breathing = breathing ?? BreathingCoordinator()
        self.focus = focus ?? FocusCoordinator()
        self.meditation = meditation ?? MeditationCoordinator()
        self.ergonomics = ergonomics ?? ErgonomicsCoordinator()

        // Pre-fill the input field from Keychain so returning users don't
        // have to re-enter their key every launch — but never store it
        // anywhere insecure ourselves.
        self.apiKeyInput = credentialStore.loadAPIKey() ?? ""

        // ---------------------------------------------------------------
        // Phase 2 — wiring. `self` is now safe to use.
        // ---------------------------------------------------------------

        // A completed breathing technique counts toward goals. Wired here
        // rather than called from the pacer view, so every entry point
        // into breathing feeds goals identically — and only once.
        self.breathing.onTechniqueCompleted = { [weak self] in
            self?.goals.recordBreathingCompleted()
        }

        // Reuse the existing suppression concept rather than adding a
        // second one — no desk nudges during focus, meditation, or a
        // breathing exercise.
        self.ergonomics.isSuppressed = { [weak self] in
            guard let self else { return true }
            return self.isBiofeedbackActive
                || self.focus.suppressesInterruptions
                || self.meditation.engine.isRunning
        }

        if let engine = engine as? BiometricEngine {
            engine.delegate = self
        }

        forwardChildChanges()
    }

    deinit {
        sessionTimerTask?.cancel()
        gameTimerTask?.cancel()
        blinkResetTask?.cancel()
        biofeedbackResetTask?.cancel()
        // `childObservers` cancels itself on deallocation.
    }

    // MARK: - Nested Observation

    /// Re-publishes child coordinators' changes as changes to `AppModel`.
    ///
    /// SwiftUI does **not** observe nested `ObservableObject`s. A view
    /// holding `@EnvironmentObject var model: AppModel` and reading
    /// `model.meditation.activeMeditation` will never re-render when that
    /// property changes, because `AppModel` itself published nothing —
    /// the change happened one level down.
    ///
    /// This is the classic silent failure of composed view models: the
    /// code looks obviously correct, the state genuinely updates, and the
    /// UI simply never moves. Forwarding each child's `objectWillChange`
    /// makes `model.<child>.<property>` reads behave the way anyone
    /// reading `ContentView` would assume they do.
    ///
    /// Trade-off: this re-renders any view observing `AppModel` on *any*
    /// child update, including ones it doesn't read. Cheap at this size.
    /// If the root view ever becomes expensive to evaluate, the more
    /// precise alternative is giving each view its own `@ObservedObject`
    /// for the coordinator it actually needs — which several views
    /// (`GoalsDashboardView`, `BreathingLibraryView`) already do.
    ///
    /// Any new coordinator must be added to `children` below, or its
    /// state changes will silently fail to reach the UI.
    private func forwardChildChanges() {
        let children: [any ObservableObject] = [
            prediction, goals, breathing, focus, meditation, ergonomics
        ]

        for child in children {
            guard let publisher = child.objectWillChange as? ObservableObjectPublisher else {
                continue
            }

            publisher
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.objectWillChange.send() }
                .store(in: &childObservers)
        }
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
        ergonomics.startSession()
    }

    func stop() {
        engine.stop()
        isRunning = false
        processingStatus = "stopped"

        stopGame()
        stopSessionTimer()

        // Tear the breathing overlay down properly rather than only
        // clearing the flag — the pacer is driven by
        // `breathing.activeTechnique`, so setting `isBiofeedbackActive`
        // alone would leave it on screen after the session ended.
        dismissBiofeedback()

        // `stop()` is called exactly once and its return value is the
        // finished recording. Calling it twice returns nil the second
        // time, which would hand `goals.refresh` no session and silently
        // drop that session's personal records.
        let finished = sessionRecorder.stop()
        goals.refresh(latestSession: finished)

        ergonomics.endSession()
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

        // Single fan-out point for gaze, mirroring `recomputeDerivedState`
        // for stress. No-ops when no ergonomics session is running.
        ergonomics.ingest(gaze: gaze)
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

    // MARK: - Breathing

    /// Single teardown path for a breathing intervention, however it
    /// started. Both the flag and the overlay state are cleared here, so
    /// no caller has to remember to do both.
    func dismissBiofeedback() {
        biofeedbackResetTask?.cancel()
        biofeedbackResetTask = nil
        isBiofeedbackActive = false
        breathing.dismissActive()
    }

    /// Starts a breathing intervention on the user's own initiative (e.g.
    /// tapping "Start breathing" on a predictive alert), as opposed to
    /// `triggerBiofeedback()` firing automatically at the threshold.
    func beginBreathingManually() {
        prediction.dismissAlert()
        triggerBiofeedback()
    }

    // MARK: - Private: Session Lifecycle

    private func resetSessionState() {
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

        dismissBiofeedback()
        stressScore = 0
        stressLevel = .calm
        stressHistory = []
        emotionalState = .calm
        emotionIntensity = 0

        // Clear the trend window so the tail of the previous session
        // doesn't leak into the new one's slope.
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

    /// Single fan-out point for a fresh stress score.
    ///
    /// Every consumer is fed exactly once here. That matters most for
    /// `prediction`: it holds a rolling window and fits a regression
    /// against sample timestamps, so feeding it the same score twice
    /// halves the effective window and pushes two points onto the same
    /// instant, distorting the slope.
    private func recomputeDerivedState() {
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

        // Practice-mode tracking. Both no-op when inactive.
        focus.ingest(stressScore: score)
        meditation.ingest(stressScore: score)

        sessionRecorder.capture(
            stressScore: score,
            heartRate: latestPulse,
            breathingRate: latestBreathing,
            eda: latestEDA,
            emotionalState: state.label,
            gazeConfidence: gaze.confidence
        )

        // One call, with the full suppression picture. An earlier
        // unsuppressed call would defeat focus/meditation quiet mode
        // entirely — the alert would already have fired by the time the
        // suppressed call ran.
        prediction.ingest(
            score: score,
            interventionActive: isBiofeedbackActive
                || focus.suppressesInterruptions
                || meditation.engine.isRunning
        )

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
        breathing.beginSelected()

        biofeedbackResetTask?.cancel()
        biofeedbackResetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled else { return }
            // Full teardown, not just the flag — otherwise the pacer
            // overlay stays on screen indefinitely after the timeout.
            self?.dismissBiofeedback()
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
