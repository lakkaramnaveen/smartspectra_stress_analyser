import AppKit

/// Observes which app is frontmost using `NSWorkspace`'s public
/// application-activation notifications.
///
/// This needs no special permission and no Accessibility entitlement —
/// unlike reading another app's window titles or content, which *does*
/// require Accessibility access and isn't what this does. `NSWorkspace`
/// only ever tells a process which app has focus and when that changes;
/// it has no way to see what's inside that app. That ceiling isn't a
/// restraint this class is choosing to honour — it's the only thing the
/// framework can technically report.
@MainActor
final class AppUsageMonitor {

    /// Fired each time a focus session completes — the previously
    /// frontmost app has lost focus to a different one.
    var onSessionCompleted: ((AppFocusSession) -> Void)?

    private var currentBundleID: String?
    private var currentAppName: String?
    private var currentStart: Date?
    private var observer: NSObjectProtocol?

    func start() {
        stop()  // idempotent — safe to call while already running

        // Seed with whatever's frontmost right now, so the very first
        // switch after starting closes a real, correctly-timed session
        // rather than silently discarding the time spent before the
        // first activation notification fires.
        if let app = NSWorkspace.shared.frontmostApplication {
            beginTracking(app)
        }

        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            self?.handleActivation(app)
        }
    }

    func stop() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observer = nil
        closeCurrentSession(at: Date())
    }

    // MARK: - Private

    private func handleActivation(_ app: NSRunningApplication) {
        closeCurrentSession(at: Date())
        beginTracking(app)
    }

    private func beginTracking(_ app: NSRunningApplication) {
        currentBundleID = app.bundleIdentifier ?? "unknown"
        currentAppName = app.localizedName ?? "Unknown app"
        currentStart = Date()
    }

    private func closeCurrentSession(at end: Date) {
        defer {
            currentBundleID = nil
            currentAppName = nil
            currentStart = nil
        }

        guard let bundleID = currentBundleID, let name = currentAppName, let start = currentStart else {
            return
        }

        // Sub-second flickers — a system dialog flashing in and back out
        // — aren't meaningful usage and would just add noise to the
        // association analysis.
        guard end.timeIntervalSince(start) >= 1 else { return }

        onSessionCompleted?(AppFocusSession(bundleID: bundleID, appName: name, start: start, end: end))
    }

    deinit {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
}
