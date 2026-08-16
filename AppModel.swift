import AppKit
import Combine
import SwiftUI

/// Root view model for the Composure workspace.
///
/// A thin coordinator. Parsing, formatting, and orchestration live here;
/// everything else is a composed dependency:
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
///   - `RecoveryCoordinator`         — post-peak descent tracking
///   - `SleepCoordinator`            — rest log & its association with stress
///   - `HRVCoordinator`              — beat variability from the pulse waveform
///   - `CoachCoordinator`            — technique effectiveness, ranked from real usage
///   - `HealthSyncCoordinator`       — buffers data for export toward Apple Health
///
/// One thing this class does *not* own: which profile is active.
/// `AppModel` is now scoped to a single `UserProfile` at construction
/// time — every coordinator above with its own on-disk store is rooted
/// under that profile's storage directory, decided once in `init` and
/// fixed for this instance's lifetime. Switching to a different family
/// member is handled one layer up, by discarding this `AppModel`
/// entirely and constructing a fresh one for the new profile — see the
/// note on `ProfileScopedContentView` in the app entry point for why
/// that's the right boundary rather than trying to hot-swap a dozen
/// coordinators' stores in place.
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

    /// The family member this instance belongs to. Determines the
    /// storage root every coordinator below resolves its files under —
    /// see `UserProfile.storageRoot`.
    let profile: UserProfile

    private let engine: BiometricEngineProviding
    private let credentialStore: CredentialStoring
    private let scoringEngine: StressScoringEngine
    private let sessionRecorder: SessionRecorder

    // Was `private` — now internal so `ContentView` can hand the same
    // store to `SessionHistoryView` and `InsightsDashboardView`, which
    // otherwise default to an *unnamespaced* `FileSessionStore()` of
    // their own and would silently read the wrong profile's data (or,
    // pre-profiles, a redundant-but-harmless second instance pointed at
    // the same folder). Multiple views must share the one store the
    // active profile actually resolved to, not each construct their own.
    let sessionStore: SessionStoring

    // Exposed so views can bind to them directly. `let`, because nothing
    // should ever swap which coordinator the model points at — their
    // *contents* change, not their identity.
    let prediction: StressPredictionCoordinator
    let goals: GoalsCoordinator
    let breathing: BreathingCoordinator
    let focus: FocusCoordinator
    let meditation: MeditationCoordinator
    let ergonomics: ErgonomicsCoordinator
    let recovery: RecoveryCoordinator
    let sleep: SleepCoordinator
    let hrv: HRVCoordinator
    let coach: CoachCoordinator
    let healthSync: HealthSyncCoordinator

    /// Subscriptions forwarding child coordinators' change notifications
    /// into our own. See `forwardChildChanges()`.
    private var childObservers: Set<AnyCancellable> = []

    /// Baseline seeding is done once per launch, lazily on first start.
    private var hasSeededRecoveryBaseline = false

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
    ///
    /// `profile` defaults to `.default`, whose `storageRoot` is literally
    /// `"Composure"` — the exact path every store already used before
    /// profiles existed. Every pre-existing call site in this codebase
    /// (every `#Preview`, every test) constructs `AppModel()` with no
    /// `profile` argument and keeps working, reading and writing exactly
    /// where it always did. Profile-scoped storage only kicks in once a
    /// caller passes a real, non-default profile — see
    /// `ProfileScopedContentView`.
    init(
        profile: UserProfile = .default,
        engine: BiometricEngineProviding = BiometricEngine(),
        credentialStore: CredentialStoring = KeychainCredentialStore(),
        scoringEngine: StressScoringEngine = StressScoringEngine(),
        sessionRecorder: SessionRecorder? = nil,
        sessionStore: SessionStoring? = nil,
        prediction: StressPredictionCoordinator? = nil,
        goals: GoalsCoordinator? = nil,
        breathing: BreathingCoordinator? = nil,
        focus: FocusCoordinator? = nil,
        meditation: MeditationCoordinator? = nil,
        ergonomics: ErgonomicsCoordinator? = nil,
        recovery: RecoveryCoordinator? = nil,
        sleep: SleepCoordinator? = nil,
        hrv: HRVCoordinator? = nil,
        coach: CoachCoordinator? = nil,
        healthSync: HealthSyncCoordinator? = nil
    ) {
        // ---------------------------------------------------------------
        // Phase 1 — assign EVERY stored property.
        //
        // Nothing below this block may touch `self` until all of them are
        // set: Swift forbids using `self` in an initializer until the
        // instance is fully formed. Assigning a coordinator *after*
        // something like `engine.delegate = self` is a compile error, and
        // an easy one to introduce when adding a dependency, so keeping
        // every assignment together makes that mistake impossible.
        // ---------------------------------------------------------------
        self.profile = profile
        self.engine = engine
        self.credentialStore = credentialStore
        self.scoringEngine = scoringEngine

        // One shared session store, rooted under this profile, handed to
        // every coordinator that needs to read or write session history
        // — rather than each defaulting to its own instance and hoping
        // they all land on the same path by coincidence of matching
        // default strings, which is what happened before profiles
        // existed (harmless there, since `FileSessionStore` is stateless
        // between instances, but no longer harmless once the path itself
        // varies per profile).
        let resolvedSessionStore = sessionStore ?? FileSessionStore(
            appSupportSubdirectory: "\(profile.storageRoot)/Sessions"
        )
        self.sessionStore = resolvedSessionStore
        self.sessionRecorder = sessionRecorder ?? SessionRecorder(store: resolvedSessionStore)

        self.prediction = prediction ?? StressPredictionCoordinator()
        self.goals = goals ?? GoalsCoordinator(
            store: FileGoalsStore(appSupportSubdirectory: profile.storageRoot),
            sessionStore: resolvedSessionStore
        )
        self.breathing = breathing ?? BreathingCoordinator(
            store: FileBreathingPreferencesStore(appSupportSubdirectory: profile.storageRoot)
        )
        self.focus = focus ?? FocusCoordinator()
        self.meditation = meditation ?? MeditationCoordinator(
            store: FileMeditationPreferencesStore(appSupportSubdirectory: profile.storageRoot)
        )
        self.ergonomics = ergonomics ?? ErgonomicsCoordinator(
            store: FileErgonomicsConfigStore(appSupportSubdirectory: profile.storageRoot)
        )
        // No store of its own — `recovery` seeds its baseline by reading
        // `resolvedSessionStore` directly in `seedRecoveryBaselineIfNeeded()`,
        // so it's automatically profile-correct with no changes here.
        self.recovery = recovery ?? RecoveryCoordinator()
        self.sleep = sleep ?? SleepCoordinator(
            store: FileSleepStore(appSupportSubdirectory: profile.storageRoot),
            sessionStore: resolvedSessionStore
        )
        self.hrv = hrv ?? HRVCoordinator(
            store: FileHRVStore(appSupportSubdirectory: profile.storageRoot)
        )
        self.coach = coach ?? CoachCoordinator(
            store: FileCoachStore(appSupportSubdirectory: profile.storageRoot),
            sessionStore: resolvedSessionStore
        )
        self.healthSync = healthSync ?? HealthSyncCoordinator(
            store: FileHealthSyncStore(appSupportSubdirectory: profile.storageRoot)
        )

        // Deliberately NOT profile-scoped. The SmartSpectra API key is a
        // household/device license, not personal data — every family
        // member sharing this Mac shares the same subscription, so it
        // stays in the one Keychain entry `KeychainCredentialStore`
        // already used before profiles existed.
        //
        // Pre-fill the input field from Keychain so returning users don't
        // have to re-enter their key every launch — but never store it
        // anywhere insecure ourselves.
        self.apiKeyInput = credentialStore.loadAPIKey() ?? ""

        // ---------------------------------------------------------------
        // Phase 2 — wiring. `self` is now safe to use.
        //
        // Cheap in-memory work only. No disk reads: `init` runs during
        // window construction, so anything touching storage is deferred
        // to `start()` or to the view's `.task`.
        // ---------------------------------------------------------------

        // A completed breathing technique counts toward goals. Wired here
        // rather than from the pacer view, so every entry point into
        // breathing feeds goals identically — and only once.
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
    /// UI simply never moves.
    ///
    /// Trade-off: this re-renders any view observing `AppModel` on *any*
    /// child update, including ones it doesn't read. Cheap at this size.
    /// If the root view ever becomes expensive to evaluate, the more
    /// precise alternative is giving each view its own `@ObservedObject`
    /// for the coordinator it needs — which several views already do.
    ///
    /// Any new coordinator must be added to `children` below, or its
    /// state changes will silently fail to reach the UI.
    private func forwardChildChanges() {
        let children: [any ObservableObject] = [
            prediction, goals, breathing, focus,
            meditation, ergonomics, recovery, sleep, hrv, coach, healthSync
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
        recovery.startSession()

        seedRecoveryBaselineIfNeeded()
        hrv.startSession()
        healthSync.startSession()
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
        recovery.endSession()
        hrv.endSession()

        // If a breathing or meditation session was still mid-flight when
        // monitoring stopped, close it out rather than silently drop the
        // partial data — a session cut short by "Stop" still happened.
        coach.flush()
        healthSync.endSession()

        // A new session gives the sleep association fresh data to join
        // against, so refresh it once the recording has landed.
        Task { await sleep.analyse() }
    }

    /// Reads recent history to establish the user's typical stress level,
    /// so recovery has a meaningful "usual range" from the first spike
    /// rather than waiting for this session to accumulate calm samples.
    ///
    /// Deferred out of `init` and run once per launch: this touches disk,
    /// and doing it during window construction puts file reads directly
    /// in the app's launch path.
    private func seedRecoveryBaselineIfNeeded() {
        guard !hasSeededRecoveryBaseline else { return }
        hasSeededRecoveryBaseline = true

        let recent = sessionStore.loadSummaries()
            .prefix(20)
            .compactMap { try? sessionStore.load(id: $0.id) }

        recovery.seedBaseline(from: Array(recent))
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
    /// started. The flag, the overlay state, and the recovery quiet
    /// period are all handled here, so no caller has to remember all
    /// three.
    func dismissBiofeedback() {
        biofeedbackResetTask?.cancel()
        biofeedbackResetTask = nil
        isBiofeedbackActive = false
        breathing.dismissActive()

        // Starts recovery's quiet period. Readings drop sharply right
        // after a breathing session, which is exactly when the recovery
        // panel would otherwise fire — turning one intervention into two
        // back-to-back interruptions.
        recovery.noteInterventionEnded()
    }

    /// Starts a breathing intervention on the user's own initiative (e.g.
    /// tapping "Start breathing" on a predictive alert or the recovery
    /// panel), as opposed to `triggerBiofeedback()` firing automatically
    /// at the threshold.
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
                // Fed here rather than in `recomputeDerivedState`: this
                // is the actual SDK-reported reading, not the derived
                // stress score, so it belongs at the point where the SDK
                // value itself becomes available.
                healthSync.noteHeartRate(parsed.value)
                recomputeDerivedState()
            } else if line.hasPrefix("Breathing rate:"), let parsed = parseRate(line) {
                vitalsDisplay.breathingRPM = formattedInt(parsed.value)
                vitalsDisplay.breathingConfidence = parsed.confidence ?? ""
                latestBreathing = parsed.value
                healthSync.noteRespiratoryRate(parsed.value)
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

        if !arterialPressure.isEmpty {
            hrv.ingestWaveform(arterialPressure)
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
    /// `prediction`, `recovery`, and `coach`: all three hold rolling
    /// windows keyed on sample timestamps or sample order, so feeding
    /// any of them the same score twice halves the effective window and
    /// pushes two points onto the same instant.
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

        // Practice-mode tracking. All no-op when inactive.
        focus.ingest(stressScore: score)
        meditation.ingest(stressScore: score)
        hrv.noteStress(score)

        sessionRecorder.capture(
            stressScore: score,
            heartRate: latestPulse,
            breathingRate: latestBreathing,
            eda: latestEDA,
            emotionalState: state.label,
            gazeConfidence: gaze.confidence
        )

        // Computed once and shared: prediction and recovery use the same
        // definition of "the user is already being attended to", and
        // letting them drift apart is how one ends up interrupting during
        // a session the other correctly stayed quiet for.
        let attentionOccupied = isBiofeedbackActive
            || focus.suppressesInterruptions
            || meditation.engine.isRunning

        prediction.ingest(score: score, interventionActive: attentionOccupied)
        recovery.ingest(score: score, suppressed: attentionOccupied)

        // Coach needs to know *which* intervention is running, not just
        // whether one is — it's measuring per-technique effectiveness,
        // not gating an alert. Breathing is checked first: the two
        // overlays are mutually exclusive in the UI in practice, but
        // nothing enforces that at the type level, so a deterministic
        // tie-break is worth having.
        let activeIntervention: InterventionKind? = {
            if let technique = breathing.activeTechnique {
                return .breathing(id: technique.id, name: technique.name)
            }
            if let activeMeditation = meditation.activeMeditation {
                return .meditation(id: activeMeditation.id, name: activeMeditation.title)
            }
            return nil
        }()
        coach.ingest(score: score, activeIntervention: activeIntervention)

        // Same activity signal Coach just used, reused rather than
        // independently re-derived — "a mindful practice is active" has
        // exactly one definition in this app, and computing it twice
        // would be a second place for that definition to drift.
        healthSync.noteMindfulBoundary(
            active: activeIntervention != nil,
            source: activeIntervention?.name
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
