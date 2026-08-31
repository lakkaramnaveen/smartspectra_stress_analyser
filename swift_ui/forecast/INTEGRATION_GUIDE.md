# Stress Prediction & Alerts — Integration Guide

Drop all six files into a `prediction/` group next to your existing
`session/` group:

```
swift_ui/
├── prediction/
│   ├── StressForecast.swift              → models (direction, forecast)
│   ├── StressTrendAnalyzer.swift         → pure math (least-squares fit)
│   ├── InterventionAlertPolicy.swift     → when to interrupt someone
│   ├── StressNotificationService.swift   → delivery (protocol + impls)
│   ├── StressPredictionCoordinator.swift → facade AppModel composes
│   └── StressPredictionViews.swift       → pill, card, banner
├── session/
└── ...
```

No third-party dependencies. Reuses your existing `RollingBuffer`,
`BrandColor`, and `Spacing`.

---

## 1. Compose the coordinator into `AppModel`

```swift
// AppModel.swift — property list, next to sessionRecorder

private let sessionRecorder: SessionRecorder
let prediction: StressPredictionCoordinator   // ← add (not private: views read it)
```

```swift
// AppModel.swift — init

init(
    engine: BiometricEngineProviding = BiometricEngine(),
    credentialStore: CredentialStoring = KeychainCredentialStore(),
    scoringEngine: StressScoringEngine = StressScoringEngine(),
    sessionRecorder: SessionRecorder? = nil,
    prediction: StressPredictionCoordinator? = nil        // ← add, nil-defaulted
) {
    self.engine = engine
    self.credentialStore = credentialStore
    self.scoringEngine = scoringEngine
    self.sessionRecorder = sessionRecorder ?? SessionRecorder()
    self.prediction = prediction ?? StressPredictionCoordinator()   // ← add
    ...
}
```

**Why `nil`-defaulted again:** exactly the bug you hit last time.
`StressPredictionCoordinator` is `@MainActor`, and default-argument
expressions evaluate in a non-isolated context even inside a
`@MainActor` init. Constructing it in the body avoids that.

## 2. Feed the coordinator from `recomputeDerivedState()`

One line, right next to the existing `sessionRecorder.capture(...)`:

```swift
// AppModel.swift — recomputeDerivedState()

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

prediction.ingest(                                        // ← add
    score: score,
    interventionActive: isBiofeedbackActive
)

if scoringEngine.shouldTriggerIntervention(forStressScore: score), !isBiofeedbackActive {
    triggerBiofeedback()
}
```

## 3. Reset trend state between sessions

```swift
// AppModel.swift — resetSessionState()

emotionalState = .calm
emotionIntensity = 0
prediction.reset()                                        // ← add
```

Without this, the tail of one session's stress curve leaks into the next
session's slope and produces a bogus forecast in the first few seconds.

## 4. Let the banner trigger a breathing session

`isBiofeedbackActive` has a `private(set)` setter, so views can't set it.
Add a public method next to `dismissBiofeedback()`:

```swift
// AppModel.swift

/// Starts a breathing intervention on the user's own initiative (e.g.
/// tapping "Start breathing" on a predictive alert), as opposed to
/// `triggerBiofeedback()` which fires automatically at the threshold.
func beginBreathingManually() {
    prediction.dismissAlert()
    triggerBiofeedback()
}
```

---

## 5. Show the trend pill in the status bar

`ContentView.swift`, in `mainWorkspace`:

```swift
VStack {
    HStack {
        validationPill
        Spacer()
        StressTrendPill(forecast: model.prediction.forecast)   // ← add
    }
    .padding(18)

    Spacer()
}
```

## 6. Show the alert banner as an overlay

Still in `ContentView.swift`, inside the root `ZStack` — above the
sidebar, below the game overlay:

```swift
if let alert = model.prediction.activeAlert {
    VStack {
        StressAlertBanner(
            alert: alert,
            onDismiss: { model.prediction.dismissAlert() },
            onStartBreathing: { model.beginBreathingManually() }
        )
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .frame(maxWidth: 520)

        Spacer()
    }
    .transition(.move(edge: .top).combined(with: .opacity))
    .zIndex(500)
}
```

And add it to the animation list so it slides rather than pops:

```swift
.animation(.easeInOut, value: showGameFullscreen)
.animation(.spring(response: 0.4), value: model.prediction.activeAlert)   // ← add
```

## 7. Add the forecast card to the Stress tab

`StressVisualizationView.swift`, just under the header:

```swift
StressForecastCard(forecast: model.prediction.forecast)
```

---

## Design notes

**Why regression against elapsed time, not sample index.** The SDK
delivers metrics on an irregular cadence. Regressing against index
assumes even spacing, so a stuttering feed would distort the slope.
`StressTrendAnalyzer` regresses against `timeIntervalSince(first)`.

**Why R² gates the ETA.** A noisy scatter can still yield a steep
best-fit line. Without a goodness-of-fit floor, the UI would confidently
display "critical in ~2 min" derived from pure noise. Below
`minimumConfidenceForETA` the analyzer returns `nil` and the UI simply
omits the estimate rather than inventing one.

**Why the policy is its own type.** The judgement "is this worth
interrupting a human being right now" is genuinely separate from both
the math and the delivery mechanism, and it's the part most likely to
need tuning after real use. Cooldown, minimum score, and confidence
floor all live in `AlertPolicyConfig`.

**Why no notification sound.** A chime is a startle response. Using one
to announce rising stress would measurably worsen the thing being
measured.

**On the honesty of the estimate.** A straight-line extrapolation of a
two-minute window is a weak predictor — stress genuinely doesn't move
linearly. The card says so in small print, and the copy uses "on this
trend" rather than "you will". Overstating this would be the easiest way
to lose a user's trust the first time the estimate misses.

---

## Tests

```swift
import XCTest

final class StressTrendAnalyzerTests: XCTestCase {

    func testDetectsRisingTrend() {
        var analyzer = StressTrendAnalyzer()
        let start = Date()

        // Climb 0.30 → 0.60 over 60 samples at 1Hz.
        var forecast = StressForecast.empty
        for i in 0..<60 {
            forecast = analyzer.ingest(
                score: 0.30 + Double(i) * 0.005,
                at: start.addingTimeInterval(Double(i))
            )
        }

        XCTAssertEqual(forecast.direction, .rising)
        XCTAssertGreaterThan(forecast.slopePerSecond, 0)
        XCTAssertGreaterThan(forecast.confidence, 0.95)  // near-perfect line
        XCTAssertNotNil(forecast.timeToThreshold)
    }

    func testFlatSeriesReportsSteady() {
        var analyzer = StressTrendAnalyzer()
        let start = Date()

        var forecast = StressForecast.empty
        for i in 0..<40 {
            forecast = analyzer.ingest(score: 0.5, at: start.addingTimeInterval(Double(i)))
        }

        XCTAssertEqual(forecast.direction, .steady)
        XCTAssertNil(forecast.timeToThreshold)
    }

    func testRefusesToForecastBelowMinimumSamples() {
        var analyzer = StressTrendAnalyzer()
        let forecast = analyzer.ingest(score: 0.8)

        XCTAssertEqual(forecast.direction, .insufficientData)
        XCTAssertNil(forecast.timeToThreshold)
    }

    func testNoisyDataSuppressesETA() {
        var analyzer = StressTrendAnalyzer()
        let start = Date()

        // Wild oscillation with no real trend — slope may be nonzero but
        // R² should be far too low to extrapolate from.
        var forecast = StressForecast.empty
        for i in 0..<60 {
            let noisy = i % 2 == 0 ? 0.2 : 0.9
            forecast = analyzer.ingest(score: noisy, at: start.addingTimeInterval(Double(i)))
        }

        XCTAssertLessThan(forecast.confidence, 0.35)
        XCTAssertNil(forecast.timeToThreshold)
    }
}

final class InterventionAlertPolicyTests: XCTestCase {

    private func risingForecast(score: Double = 0.6, eta: TimeInterval = 120) -> StressForecast {
        StressForecast(
            currentScore: score,
            direction: .rising,
            slopePerSecond: 0.002,
            confidence: 0.8,
            timeToThreshold: eta,
            sampleCount: 60
        )
    }

    func testRaisesAlertForCredibleRisingTrend() {
        var policy = InterventionAlertPolicy()
        let alert = policy.evaluate(risingForecast(), interventionAlreadyActive: false)
        XCTAssertNotNil(alert)
    }

    func testSuppressesDuringActiveIntervention() {
        var policy = InterventionAlertPolicy()
        let alert = policy.evaluate(risingForecast(), interventionAlreadyActive: true)
        XCTAssertNil(alert)
    }

    func testRespectsCooldown() {
        var policy = InterventionAlertPolicy()
        let now = Date()

        XCTAssertNotNil(policy.evaluate(risingForecast(), now: now, interventionAlreadyActive: false))

        // 60s later — well inside the 5-minute cooldown.
        let second = policy.evaluate(
            risingForecast(),
            now: now.addingTimeInterval(60),
            interventionAlreadyActive: false
        )
        XCTAssertNil(second)
    }

    func testIgnoresLowStressEvenWhenRising() {
        var policy = InterventionAlertPolicy()
        let alert = policy.evaluate(
            risingForecast(score: 0.15),
            interventionAlreadyActive: false
        )
        XCTAssertNil(alert)
    }
}
```
