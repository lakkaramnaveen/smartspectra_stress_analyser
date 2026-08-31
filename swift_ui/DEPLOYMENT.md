# 🚀 Composure v3 - Integration & Deployment Guide

## Quick Start (10 Minutes)

### Prerequisites

- Xcode 14+ (Swift 5.9+)
- macOS 12+ SDK
- SmartSpectra SDK (SmartSpectraRunner.mm, SmartSpectraRunner.h)
- A valid SmartSpectra API key

### Step 1: Project Setup in Xcode

1. **Create a new macOS SwiftUI project** (or use your existing Composure project)
2. **Delete** the auto-generated `ContentView.swift`
3. **File → Add Files to Project** and select all files from `PRODUCTION_V3/` folder
4. Ensure "Copy items if needed" is checked
5. Target membership: ✓ Your app target

### Step 2: File Structure

After adding, your project should look like:

```
YourProject/
├── Models/
│   └── DomainModels.swift
├── Services/
│   ├── BiometricEngine.swift
│   ├── KeychainCredentialStore.swift
│   └── StressScoringEngine.swift
├── Utilities/
│   └── RollingBuffer.swift
├── ViewModels/
│   └── AppModel.swift
├── Views/
│   ├── ContentView.swift
│   ├── ControlsTabView.swift
│   ├── StressVisualizationView.swift
│   ├── EmotionalDetectorView.swift
│   ├── GameTabView.swift
│   ├── BalloonHuntGameView.swift
│   └── BreathingPacerView.swift
├── Components/
│   └── SharedComponents.swift
├── SmartSpectraRunner.h
├── SmartSpectraRunner.mm
├── SmartSpectraSwiftBridge.h
├── ComposureApp.swift (your @main)
└── Info.plist
```

### Step 3: Verify SmartSpectra SDK Files

In Xcode's Project Navigator, check that these ObjC++ files are present:

- `SmartSpectraRunner.h`
- `SmartSpectraRunner.mm`
- `SmartSpectraSwiftBridge.h`

If they're red (not found):

1. Right-click on each → **File Deleted Reference**
2. **File → Add Files** → select from your SmartSpectra SDK folder
3. Ensure target membership is checked

### Step 4: Build Configuration

**Build Settings → Search Paths:**

- **Framework Search Paths:** Add any paths where SmartSpectra SDK frameworks live
- **Header Search Paths:** Add path to SmartSpectraRunner.h

**Bridging Header (if needed):**

```swift
// ComposureApp-Bridging-Header.h
#ifndef ComposureApp_Bridging_Header_h
#define ComposureApp_Bridging_Header_h

#import "SmartSpectraRunner.h"

#endif /* ComposureApp_Bridging_Header_h */
```

In Build Settings → Bridging Header: `ComposureApp-Bridging-Header.h`

### Step 5: App Entry Point

Update your `ComposureApp.swift` (or create it):

```swift
import SwiftUI

@main
struct ComposureApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 1040, minHeight: 680)
        }
    }
}
```

### Step 6: Build & Run

```bash
⌘ + B   # Build
⌘ + R   # Run
```

Expected output in Xcode console:

```
Composure version 3.0 starting...
```

No red error lines = ✅ Success!

---

## API Key Management

### How It Works

1. **User pastes API key** in the Controls tab
2. **Keychain securely stores it** (encrypted at rest)
3. **On next launch**, the key is pre-filled from Keychain
4. **Never sent unless user clicks Start**

### For Deployment

If you're shipping this to end-users, they'll provide their own API key:

1. Open the app
2. Paste key in Controls → SmartSpectra API Key field
3. Click **Start**
4. Key is saved automatically

### For Internal Testing / QA

Hardcode a test key (for ease of testing):

```swift
// In AppModel.init():
if apiKeyInput.isEmpty {
    apiKeyInput = "test-api-key-here"  // ← Will be overwritten by stored key if available
}
```

---

## First-Run Walkthrough

**User scenario:** Fresh install, first launch.

1. **App opens** → Controls tab visible
2. **API Key field is empty** (unless Keychain has a prior key)
3. **User pastes their SmartSpectra API key**
4. **Click "Start"**
   - Key is saved to Keychain
   - SDK initializes
   - Camera feed appears
   - Stress/emotion tracking begins
5. **Switch to Stress tab** → Graph populates as vitals stream in
6. **When stress ≥ 95%** → Breathing pacer auto-appears
7. **Switch to Game tab** → Select difficulty → Launch Balloon Hunt

---

## Configuration for Different Scenarios

### Scenario 1: QA / Tester Build

Lower the stress threshold for easier testing:

```swift
// In StressScoringEngine:
struct StressScoringConfig {
    var extremeStressThreshold: Double = 0.70  // ← Lower for faster testing
}
```

### Scenario 2: Demo Build

Pre-tune difficulty and sample data:

```swift
// In AppModel.init():
gameDifficulty = .hard  // Default to Hard for more impressive demo
```

### Scenario 3: Production Build

Use defaults (high threshold, balanced difficulty):

```swift
struct StressScoringConfig {
    var extremeStressThreshold: Double = 0.95  // ← User research-based
}
```

---

## Monitoring & Logging

### Add Detailed Logging

In `AppModel.swift`, add debug output:

```swift
func start() {
    print("[Session] Starting new biometric session")
    // ... existing code ...
    if let error = engine.start(apiKey: trimmedKey) {
        print("[Error] Engine failed: \(error.localizedDescription)")
        // ...
    } else {
        print("[Session] Engine initialized successfully")
    }
}
```

### Console Output to Monitor

- `[Session] Starting new...` — Session started
- `[Error] Engine failed...` — SDK error (likely bad API key)
- `[Vitals] Updated EDA...` — Live vitals arriving
- `[Stress] Score updated: 0.87` — Stress calculated
- `[Intervention] Triggering biofeedback` — Breathing pacer about to show

---

## Testing Checklist

### Pre-Launch QA

Run through this before shipping:

**Startup (5 min)**
- [ ] App launches
- [ ] Controls tab visible, API key field empty
- [ ] Can paste API key
- [ ] Click "Start" → successful (no error message)
- [ ] Camera feed appears

**Vitals Streaming (5 min)**
- [ ] Stress tab shows graph (populates as data arrives)
- [ ] Heart rate / breathing rate values update
- [ ] Stress score changes (0–100%)
- [ ] Emotional state switches between Calm/Focused/Anxious/Stressed

**Breathing Pacer (3 min)**
- [ ] Trigger high stress (simulator or real data)
- [ ] Pacer appears only when stress ≥ 95%
- [ ] Shows 6 breathing cycles
- [ ] Can click "Exit" to dismiss early
- [ ] Auto-dismisses after 60 sec

**Game (5 min)**
- [ ] Game tab shows difficulty selector
- [ ] Select "Extreme" difficulty
- [ ] Click "Launch Balloon Hunt"
- [ ] Fullscreen game appears
- [ ] Balloons spawn and float upward
- [ ] Blink detection shows in crosshair
- [ ] Can pop balloons (score increases)
- [ ] Game completes after ~30 sec (score/time shown)

**Edge Cases (3 min)**
- [ ] Empty API key → Click Start → Error: "No SmartSpectra API key configured"
- [ ] Invalid API key → Error: "Credential refresh failed... 401"
- [ ] Stop mid-session → Session stats preserved
- [ ] Switch tabs during data streaming → No crashes

**Total: ~25 min for thorough QA**

---

## Performance Optimization

### For Slower Macs

If you notice lag during the game:

1. **Reduce balloon cap** in `BalloonHuntGameView`:
   ```swift
   guard balloons.count < 15 else { return }  // ← Was 20
   ```

2. **Lower game FPS** (trade smoothness for CPU):
   ```swift
   try? await Task.sleep(for: .milliseconds(33))  // ← 30 FPS instead of 60
   ```

3. **Decrease stress history buffer** in `AppModel`:
   ```swift
   var stressBuffer = RollingBuffer<Double>(capacity: 150)  // ← Was 300
   ```

### Memory Profiling

In Xcode, use **Debug → Gauge** to monitor memory during a 10-min session:

- Expected: 3–5 MB
- If > 10 MB: check for leaked buffers (run a full session then check memory again)

---

## Deployment Steps

### 1. Code Review

- [ ] All files added to correct groups (Models, Services, etc.)
- [ ] No `.backup` or `_FIXED` files lingering
- [ ] No commented-out debug code
- [ ] All TODO comments resolved

### 2. Notarization (for App Store)

```bash
xcodebuild -scheme Composure archive -archivePath build/Composure.xcarchive
xcrun altool --notarize-app -f build/Composure.xcarchive \
  -t macos \
  -u your-apple-id@example.com \
  -p app-specific-password
```

### 3. Signing

Ensure you have a valid Developer Certificate and provisioning profile set up in Xcode.

### 4. Release Notes

Document changes from v2.x → v3.0:

```
v3.0 - Production Architecture Release

New:
- Clean layered architecture (Models → Services → ViewModels → Views)
- Secure Keychain-backed credential storage
- Service-oriented design (BiometricEngine, StressScoringEngine, CredentialStore)
- Comprehensive unit test support via dependency injection
- Improved stress threshold tuning (95%+ for intervention)

Fixed:
- Breathing pacer no longer appears at mild stress
- Game difficulty levels now properly affect physics and scoring
- Haptic feedback crash resolved
- Canvas rendering issue in stress graph fixed

Performance:
- Reduced memory footprint via RollingBuffer
- Improved thread safety (@MainActor)
- Cleaner code organization (easier maintenance)
```

### 5. Beta Testing (Optional)

If releasing through TestFlight:

1. Bump build number in Xcode → General
2. Archive → Distribute via App Store
3. Submit to TestFlight
4. Invite testers (internal team or external beta group)
5. Collect feedback for post-launch patches

---

## Post-Launch Monitoring

### Crash Reporting

Set up Crashlytics or Sentry to capture crashes:

```swift
// In SmartSpectraApp.swift
import Firebase

@main
struct ComposureApp: App {
    init() {
        FirebaseApp.configure()  // ← Add crash reporting
    }
    // ...
}
```

### Telemetry

Track key metrics (optional):

```swift
// In AppModel.start()
Analytics.log(event: "session_start", params: [
    "difficulty": gameDifficulty.rawValue,
    "timestamp": Date().timeIntervalSince1970
])
```

### User Feedback

In-app feedback button (future enhancement):

```swift
Button(action: { showFeedbackSheet = true }) {
    Label("Send Feedback", systemImage: "envelope")
}
.sheet(isPresented: $showFeedbackSheet) {
    FeedbackView()
}
```

---

## Troubleshooting & Support

### Common Issues

| Issue | Cause | Fix |
|-------|-------|-----|
| "Cannot find AppModel" build error | File not added to target | File → Target Membership, check ✓ |
| "401 Unauthenticated" at startup | Invalid/empty API key | Paste valid key in UI, click Start |
| Camera feed is black | SDK not initialized | Ensure Start button was clicked successfully |
| Stress never crosses 95% | Threshold too high for test data | Lower threshold temporarily in `StressScoringConfig` |
| Breathing pacer doesn't appear | See above | Lower threshold or trigger manually |
| Game crashes on launch | Missing BalloonHuntGameView | Add file to project and target |

### Getting Help

1. **Check console output** for error messages (⌘ + Shift + C in Xcode)
2. **Review ARCHITECTURE.md** for design context
3. **Run unit tests** to isolate the issue
4. **Enable verbose logging** in AppModel

---

## Production Readiness Checklist

- [x] All Swift files compile without warnings (verified via `xcodebuild build`)
- [x] All tests pass (`smartspectra_swift_uiTests`, 8/8)
- [ ] Performance profiled (memory < 5 MB)
- [x] Security review done (Keychain setup correct; app now also gates launch behind Touch ID/passcode via `AppLockService`)
- [x] API key management flow tested (verified live: Keychain save/load, empty-key error path)
- [x] End-to-end session tested (start → collect vitals → trigger intervention → game) — verified live this session
- [ ] Accessibility labels added to key UI elements (a handful of icon-only controls fixed; most of the app still has none — see production-readiness audit)
- [ ] App icon and metadata correct (no `.xcassets`/`AppIcon` exists yet — ships with Xcode's default icon)
- [ ] Privacy policy and terms of service prepared
- [ ] Release notes written
- [ ] Beta testing completed (if applicable)
- [ ] Crash reporting configured (none integrated)

This list previously showed every box unchecked directly above a "✅ Ready for Deployment" status — those two statements contradicted each other. The status below now reflects what's actually been verified.

---

**Version:** 3.0  
**Status:** ⚠️ Functionally verified (build, tests, and core flows confirmed working) — not yet customer-facing-ready. See the unchecked items above, plus `native_build`'s runtime dependency on the *build machine's own* Homebrew install of `smartspectra`/`opencv` (the app is not yet packaged to run on a machine without them).  
**Support:** `ARCHITECTURE.md` is referenced here but does not exist in this repo — either write it or remove the pointer.
