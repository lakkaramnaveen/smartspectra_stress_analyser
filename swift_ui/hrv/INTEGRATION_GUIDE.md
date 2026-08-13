# HRV / Beat Variability — Integration Guide

```
swift_ui/
├── hrv/
│   ├── HRVModels.swift       → measurement, quality, personal bands
│   ├── BeatDetector.swift    → peak detection → inter-beat intervals
│   ├── HRVAnalyzer.swift     → RMSSD / SDNN + personal baseline
│   ├── HRVCoordinator.swift  → store + MainActor facade
│   └── HRVTabView.swift      → the tab
└── ...
```

Reuses `CorrelationAnalyzer` from the Insights feature.

---

## Read this before wiring anything

**RMSSD cannot come from `"Pulse rate: 72.0"`.** That's an averaged BPM
value with no beat-to-beat structure in it. Running the RMSSD formula
over successive BPM readings produces a real number that is not RMSSD and
bears no relationship to it — it's the variability of a smoothed average.
This is the most common way the feature gets built wrong, and the result
looks entirely plausible.

The only usable input is `arterialPressureTrace`, peak-detected to
recover inter-beat intervals. That's what `BeatDetector` does.

**Verify the trace before trusting output.** The detector needs a raw PPG
waveform at ≥25 Hz. If `arterialPressureTrace` turns out to be smoothed,
downsampled, or already averaged, the tab will sit permanently on
"Waiting for a clean enough signal" — which is the correct behaviour, but
you'll want to know why. Quick check: log
`samples.count / batchDuration` from the first few batches. If it's below
25, or the array is only a handful of points per callback, this feature
can't work from that source.

---

## 1. Compose into `AppModel`

Phase 1 block, with the other coordinators:

```swift
let hrv: HRVCoordinator                       // ← property

hrv: HRVCoordinator? = nil                    // ← init parameter

self.hrv = hrv ?? HRVCoordinator()            // ← Phase 1 assignment
```

And `forwardChildChanges()`:

```swift
let children: [any ObservableObject] = [
    prediction, goals, breathing, focus,
    meditation, ergonomics, recovery, sleep, hrv
]
```

## 2. Session lifecycle

```swift
// start()
recovery.startSession()
hrv.startSession()                            // ← add

// stop()
recovery.endSession()
hrv.endSession()                              // ← add
```

## 3. Feed the waveform

This is the important one. In `applyTraces`, pass the arterial pressure
trace straight through:

```swift
private func applyTraces(breathing: [Double], arterialPressure: [Double], eda: [Double]) {
    breathingTrace.append(contentsOf: breathing)
    pulseTrace.append(contentsOf: arterialPressure)
    edaTrace.append(contentsOf: eda)

    // Raw waveform, not the averaged pulse-rate string — see the note
    // at the top of this guide.
    if !arterialPressure.isEmpty {
        hrv.ingestWaveform(arterialPressure)   // ← add
    }

    ...
}
```

## 4. Pair measurements against stress

In `recomputeDerivedState()`, alongside the other coordinators:

```swift
focus.ingest(stressScore: score)
meditation.ingest(stressScore: score)
hrv.noteStress(score)                          // ← add
```

## 5. Add to the Signals pane

`SignalsTab` gains a case:

```swift
enum SignalsTab: String, CaseIterable {
    case stress, emotions, heart, desk, rest    // ← add `heart`

    var label: String {
        ...
        case .heart: return "Heart"
    }
}
```

```swift
// signalsPane switch
case .heart:
    HRVTabView(coordinator: model.hrv)
```

Top-level tab count stays at seven.

---

## Design notes

### Parabolic interpolation is not optional here

At 30 fps there's 33 ms between samples. RMSSD in healthy adults is
roughly 20–90 ms. Without sub-sample peak refinement every interval is an
integer multiple of the frame period, and the resulting "variability" is
substantially a measurement of the camera's frame clock rather than the
heart. `BeatDetector.parabolicPeak` fits a three-point parabola through
each peak and its neighbours, recovering position to a fraction of a
sample.

This is a real mitigation, not a formality — but it doesn't make camera
PPG equivalent to a chest strap, which is why the output is framed the
way it is.

### Artefact rejection, two ways

A missed beat produces a doubled interval; a spurious peak produces a
halved one. Either admitted into the series inflates RMSSD enormously,
because RMSSD squares successive differences. So intervals are rejected
if they're implausible in absolute terms (outside 300–2000 ms) *or*
differ from their predecessor by more than 30%. The rejection rate is
reported with every measurement, and a window needing more than 25%
rejection is discarded rather than reported.

### No absolute zones

The spec asked for "recovery / baseline / stressed" zones. Resting RMSSD
varies by roughly an order of magnitude between healthy adults — age and
fitness dominate — so fixed millisecond cutoffs would tell most users
something false about themselves. Bands are relative to the user's own
median across their last 20+ measurements. Median, not mean: a few noisy
windows with inflated RMSSD would otherwise drag the baseline up and make
every genuine reading look "below usual".

### The interpretation stays modest

Higher short-term variability is broadly associated with parasympathetic
activity and lower with sympathetic activation — but that's a population
tendency, not a readout, and one 60-beat window says very little.
`HRVBand.note` reflects that: "often accompanies exertion, poor sleep, or
stress — though a single reading doesn't tell you which."

### Shared-source caveat on the correlation

HRV and the stress score both derive from the same camera feed. Some of
any apparent relationship between them reflects shared measurement
conditions — lighting, movement, distance — rather than physiology. The
correlation card says so, because a strong-looking r between two metrics
from one sensor is easy to over-read.

### Why the disclaimer is prominent rather than tucked away

"RMSSD" is a searchable term with published normative ranges. A user
seeing "22 ms" will find those ranges in one search and may conclude
something about their cardiac health from an unvalidated camera
measurement. The tab therefore says plainly, above the number and again
at the bottom, that this is camera-derived and shouldn't be compared to
published figures.

---

## Tests

```swift
import XCTest

final class HRVAnalyzerMathTests: XCTestCase {

    func testRMSSDOfConstantIntervalsIsZero() {
        let intervals = Array(repeating: 800.0, count: 40)
        XCTAssertEqual(HRVAnalyzer.rmssd(intervals) ?? -1, 0, accuracy: 0.0001)
    }

    func testRMSSDMatchesHandComputedValue() {
        // Successive differences: +50, -50, +50 → squares 2500 each
        // → mean 2500 → root 50.
        let intervals = [800.0, 850, 800, 850]
        XCTAssertEqual(HRVAnalyzer.rmssd(intervals) ?? -1, 50, accuracy: 0.0001)
    }

    func testSDNNMatchesHandComputedValue() {
        let intervals = [700.0, 900]
        // Mean 800, deviations ±100 → SD 100.
        XCTAssertEqual(HRVAnalyzer.sdnn(intervals) ?? -1, 100, accuracy: 0.0001)
    }

    func testMeanBPMFromIntervals() {
        // 1000 ms per beat = 60 bpm.
        let intervals = Array(repeating: 1000.0, count: 10)
        XCTAssertEqual(HRVAnalyzer.meanBPM(intervals) ?? 0, 60, accuracy: 0.0001)
    }

    func testInsufficientIntervalsReturnNil() {
        XCTAssertNil(HRVAnalyzer.rmssd([800]))
        XCTAssertNil(HRVAnalyzer.sdnn([800]))
    }
}

final class BeatDetectorTests: XCTestCase {

    /// Synthetic PPG: a clean sinusoid at a known pulse rate.
    private func syntheticWaveform(
        bpm: Double,
        seconds: Double,
        sampleRate: Double
    ) -> [Double] {
        let beatsPerSecond = bpm / 60
        let count = Int(seconds * sampleRate)
        return (0..<count).map { index in
            let t = Double(index) / sampleRate
            return sin(2 * .pi * beatsPerSecond * t)
        }
    }

    func testRejectsSubThresholdSampleRate() {
        var detector = BeatDetector()
        // 10 Hz is far too coarse for beat timing.
        let result = detector.ingest(
            samples: syntheticWaveform(bpm: 60, seconds: 5, sampleRate: 10),
            batchTimestamp: Date(),
            batchDuration: 5
        )

        XCTAssertEqual(result.quality, .unusable)
        XCTAssertTrue(result.intervals.isEmpty)
    }

    func testRecoversKnownPulseRate() {
        var detector = BeatDetector()
        let sampleRate = 30.0

        // Feed several batches so the rate estimate settles.
        var intervals: [BeatInterval] = []
        var now = Date()
        for _ in 0..<4 {
            let result = detector.ingest(
                samples: syntheticWaveform(bpm: 60, seconds: 2, sampleRate: sampleRate),
                batchTimestamp: now,
                batchDuration: 2
            )
            intervals = result.intervals
            now = now.addingTimeInterval(2)
        }

        guard !intervals.isEmpty else {
            return XCTFail("Expected intervals from a clean 60 bpm waveform")
        }

        let mean = intervals.map(\.milliseconds).reduce(0, +) / Double(intervals.count)
        // 60 bpm = 1000 ms. Allow generous tolerance — frame quantisation
        // is precisely the limitation being documented.
        XCTAssertEqual(mean, 1000, accuracy: 80)
    }

    func testImplausibleIntervalsAreRejected() {
        var detector = BeatDetector()
        // Flat signal produces no valid peaks; nothing should slip
        // through as a measurement.
        let result = detector.ingest(
            samples: Array(repeating: 0.5, count: 300),
            batchTimestamp: Date(),
            batchDuration: 10
        )
        XCTAssertTrue(result.intervals.isEmpty)
    }
}

@MainActor
final class HRVCoordinatorTests: XCTestCase {

    func testNoReadingWithoutEnoughBeats() {
        let coordinator = HRVCoordinator(store: InMemoryHRVStore())
        coordinator.startSession()

        coordinator.ingestWaveform(Array(repeating: 0.0, count: 30))
        XCTAssertNil(coordinator.latestReading)
    }

    func testBandsRequirePersonalHistory() {
        // With no stored history, a fresh reading can only be
        // `.establishing` — absolute cutoffs must never appear.
        var analyzer = HRVAnalyzer()
        let reading = analyzer.ingest(
            intervals: (0..<40).map {
                BeatInterval(
                    milliseconds: 800 + Double($0 % 5) * 10,
                    timestamp: Date()
                )
            },
            quality: .good,
            artefactRate: 0.02
        )
        XCTAssertEqual(reading?.band, .establishing)
    }
}
```
