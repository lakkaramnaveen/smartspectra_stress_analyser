# Personalized Insights — Integration Guide

Six files into a new `insights/` group, alongside `session/` and
`prediction/`:

```
swift_ui/
├── insights/
│   ├── InsightModels.swift          → models, confidence tiers, aggregates
│   ├── CorrelationAnalyzer.swift    → pure stats (Pearson, lead-lag)
│   ├── SessionAggregator.swift      → recordings → statistical buckets
│   ├── InsightGenerator.swift       → aggregates → gated natural language
│   ├── InsightsViewModel.swift      → loading + off-main-actor analysis
│   └── InsightsDashboardView.swift  → cards, heatmap, weekly chart
├── prediction/
├── session/
└── ...
```

Depends on the Session Recording feature being in place — insights are
computed entirely from `SessionRecording` history.

---

## 1. Required edit: make session models `Sendable`

The analysis runs in a `Task.detached`, so the recordings crossing that
boundary must be `Sendable`. Both types are already pure value types, so
this is a conformance declaration with no behavioural change.

In `SessionModels.swift`:

```swift
struct SessionSnapshot: Codable, Identifiable, Equatable, Sendable {   // ← add Sendable
    ...
}

struct SessionRecording: Codable, Identifiable, Equatable, Sendable {  // ← add Sendable
    ...
}
```

Without this you'll get a "captured non-Sendable type" error at the
`Task.detached` call in `InsightsViewModel`.

## 2. Add the tab

`ContentView.swift` — one case in the enum:

```swift
enum SidebarTab: String, CaseIterable {
    case controls, stress, emotions, game, history, insights   // ← add

    var label: String { rawValue.capitalized }

    var icon: String {
        switch self {
        ...
        case .insights: return "lightbulb"                     // ← add
        }
    }
}
```

And one case in `sidebarContent`:

```swift
case .insights:
    InsightsDashboardView()
```

That's the whole integration. No `AppModel` changes at all — insights
read from the session store directly rather than from live state, which
is why this feature needed no new wiring into the biometric pipeline.

---

## Design notes

**Why the evidence gating is aggressive.** Every generator method returns
`nil` unless its threshold is met, so thin history produces *fewer*
insights rather than the same number stated just as confidently. Specific
gates worth knowing about:

- Time-of-day insights need ≥4 *distinct calendar days*, not just ≥4
  sessions. Six sessions on one afternoon tell you about that afternoon.
- Hour buckets need ≥30 samples before being named as a peak or trough.
- Two buckets must differ by ≥10 percentage points before the difference
  is reported at all.
- Correlations below |r| = 0.35 are not mentioned.
- Lead-lag results under 5 seconds are discarded — a two-second "lead" is
  indistinguishable from sampling jitter.

**Why every card shows its sample count.** An observation from five
sessions and one from eighty render as identical-looking sentences. The
confidence badge and session count are the only things letting a reader
tell them apart, so they're on every card rather than hidden behind a
detail view.

**Why lead-lag is computed per session, then averaged.** Splicing separate
sessions end-to-end would create artificial discontinuities at every
boundary, and the correlation scan would happily read across those seams
as though they were continuous time.

**On naming.** The original spec called this "AI-generated insights." What
it actually is: descriptive statistics with templated prose. I've named
it accordingly throughout, and the dashboard carries a permanent
methodology note. This isn't pedantry — a user who believes an algorithm
diagnosed their afternoons will act on it more readily than one who
understands they're reading an average. If you later add a real model,
that's the point to revisit the wording.

**Why "not medical assessment" is in the UI.** The app measures
physiological signals and makes claims about the user's stress patterns.
Someone could reasonably read "your stress peaks 2–4 PM" as clinical
information about themselves. One sentence of framing is cheap insurance
against that.

---

## Performance

Aggregation walks every snapshot across every session, and the lead-lag
scan is O(maxLag × samples) per session. For 200 sessions at 90 samples
each that's ~18k snapshots and 200 scans — comfortably under a second on
Apple silicon, but enough to drop frames if run inline on a view update,
hence `Task.detached`.

If history grows past a few thousand sessions, the natural next step is
caching `InsightAggregates` and invalidating on new session save, rather
than recomputing from scratch on every tab visit.

---

## Tests

```swift
import XCTest

final class CorrelationAnalyzerTests: XCTestCase {

    func testPerfectPositiveCorrelation() {
        let xs = [1.0, 2, 3, 4, 5]
        let ys = [2.0, 4, 6, 8, 10]
        let r = CorrelationAnalyzer.pearson(xs, ys)
        XCTAssertEqual(r ?? 0, 1.0, accuracy: 0.0001)
    }

    func testPerfectNegativeCorrelation() {
        let xs = [1.0, 2, 3, 4, 5]
        let ys = [10.0, 8, 6, 4, 2]
        let r = CorrelationAnalyzer.pearson(xs, ys)
        XCTAssertEqual(r ?? 0, -1.0, accuracy: 0.0001)
    }

    func testFlatSeriesReturnsNilNotZero() {
        // Zero variance means "undefined", not "no correlation".
        let xs = [3.0, 3, 3, 3, 3]
        let ys = [1.0, 2, 3, 4, 5]
        XCTAssertNil(CorrelationAnalyzer.pearson(xs, ys))
    }

    func testDetectsKnownLead() {
        // `leading` is `following` shifted 5 samples earlier.
        let base = (0..<60).map { sin(Double($0) / 5) }
        let leading = base
        let following = Array(repeating: 0.0, count: 5) + base.dropLast(5)

        let result = CorrelationAnalyzer.bestLead(
            leading: leading,
            following: following,
            maxLagSamples: 15
        )

        XCTAssertEqual(result?.lagSamples, 5)
        XCTAssertGreaterThan(result?.correlation ?? 0, 0.9)
    }
}

final class InsightGeneratorTests: XCTestCase {

    func testProducesNothingBelowMinimumSessions() {
        let aggregates = InsightAggregates(
            hourBuckets: [], weekdayBuckets: [], weeklyTrend: [],
            totalSessions: 2, totalSnapshots: 180, distinctDays: 2,
            heartRateCorrelation: 0.9, breathingCorrelation: 0.9,
            edaCorrelation: 0.9, edaLeadSeconds: 30, edaLeadStrength: 0.8
        )

        // Every correlation here is strong, but two sessions isn't
        // enough evidence to say anything — the gate should win.
        XCTAssertTrue(InsightGenerator().generate(from: aggregates).isEmpty)
    }

    func testSuppressesTimeOfDayWithTooFewDistinctDays() {
        let buckets = (9...17).map {
            HourBucket(hour: $0, averageStress: $0 == 14 ? 0.8 : 0.3,
                       sampleCount: 100, distinctDays: 2)
        }
        let aggregates = InsightAggregates(
            hourBuckets: buckets, weekdayBuckets: [], weeklyTrend: [],
            totalSessions: 10, totalSnapshots: 900, distinctDays: 2,
            heartRateCorrelation: nil, breathingCorrelation: nil,
            edaCorrelation: nil, edaLeadSeconds: nil, edaLeadStrength: nil
        )

        let timeInsights = InsightGenerator()
            .generate(from: aggregates)
            .filter { $0.category == .timeOfDay }

        XCTAssertTrue(timeInsights.isEmpty)
    }

    func testReportsTimeOfDayWithSufficientSpread() {
        let buckets = (9...17).map {
            HourBucket(hour: $0, averageStress: $0 == 14 ? 0.75 : 0.35,
                       sampleCount: 100, distinctDays: 10)
        }
        let aggregates = InsightAggregates(
            hourBuckets: buckets, weekdayBuckets: [], weeklyTrend: [],
            totalSessions: 20, totalSnapshots: 1800, distinctDays: 10,
            heartRateCorrelation: nil, breathingCorrelation: nil,
            edaCorrelation: nil, edaLeadSeconds: nil, edaLeadStrength: nil
        )

        let peak = InsightGenerator()
            .generate(from: aggregates)
            .first { $0.category == .timeOfDay }

        XCTAssertNotNil(peak)
        XCTAssertTrue(peak?.headline.contains("2") ?? false)  // 2 PM window
    }

    func testIgnoresWeakCorrelations() {
        let aggregates = InsightAggregates(
            hourBuckets: [], weekdayBuckets: [], weeklyTrend: [],
            totalSessions: 20, totalSnapshots: 1800, distinctDays: 10,
            heartRateCorrelation: 0.12, breathingCorrelation: 0.09,
            edaCorrelation: -0.15, edaLeadSeconds: nil, edaLeadStrength: nil
        )

        let correlationInsights = InsightGenerator()
            .generate(from: aggregates)
            .filter { $0.category == .correlation }

        XCTAssertTrue(correlationInsights.isEmpty)
    }
}
```
