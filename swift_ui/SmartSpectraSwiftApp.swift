import SwiftUI
import AppKit
import Combine

@main
struct SmartSpectraSwiftApp: App {
    @StateObject private var model = AppModel()
    @State private var isUnlocked = false
    private let appLock: AppLocking = AppLockService()

    var body: some Scene {
        WindowGroup {
            Group {
                if isUnlocked {
                    ContentView()
                        .environmentObject(model)
                } else {
                    LockScreenView(locking: appLock, onUnlock: { isUnlocked = true })
                }
            }
            .frame(minWidth: 1040, minHeight: 680)
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
