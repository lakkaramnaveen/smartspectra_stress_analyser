import SwiftUI
import AppKit
import Combine

@main
struct SmartSpectraSwiftApp: App {
    @StateObject private var model = AppModel()
    @State private var isUnlocked = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    private let appLock: AppLocking = AppLockService()

    var body: some Scene {
        WindowGroup {
            Group {
                if !isUnlocked {
                    LockScreenView(locking: appLock, onUnlock: { isUnlocked = true })
                } else if !hasCompletedOnboarding {
                    OnboardingView(onContinue: { hasCompletedOnboarding = true })
                        .transition(.opacity)
                } else {
                    ContentView()
                        .environmentObject(model)
                }
            }
            .frame(minWidth: 1040, minHeight: 680)
            // Every view in this app hardcodes near-black backgrounds and
            // white text (BrandColor, .ultraThinMaterial over dark fills)
            // — it's a dark-only design that was never actually declared
            // as one, so in Light Mode the window's title bar rendered
            // light while everything below it was dark. Making the
            // existing design intentional rather than accidental.
            .preferredColorScheme(.dark)
            .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)) { _ in relock() }
            .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.screensDidSleepNotification)) { _ in relock() }
            .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.sessionDidResignActiveNotification)) { _ in relock() }
        }
    }

    /// Re-locks at the same moments the Mac's own lock screen would kick in
    /// — sleep, display-off, and fast user switching — so a walked-away
    /// machine doesn't keep camera video and vitals on screen indefinitely.
    /// Also stops any in-progress capture session rather than merely hiding
    /// it, since the camera shouldn't keep running while the app is locked.
    private func relock() {
        guard isUnlocked else { return }
        if model.isRunning { model.stop() }
        isUnlocked = false
    }
}
