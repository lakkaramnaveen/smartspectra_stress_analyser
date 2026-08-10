import Foundation
import UserNotifications

// MARK: - Protocol

/// Delivers alerts as system notifications.
///
/// Protocol-backed like `CredentialStoring` and `SessionStoring`: the
/// coordinator depends on this, not on `UNUserNotificationCenter`, so
/// tests can assert "an alert was delivered" without the system
/// notification machinery (or its permission prompts) being involved.
protocol StressNotifying {
    func requestAuthorizationIfNeeded() async
    func deliver(_ alert: StressAlert) async
}

// MARK: - System Implementation

final class SystemStressNotifier: StressNotifying {
    private let center: UNUserNotificationCenter
    private var hasRequestedAuthorization = false

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    /// Requests notification permission once per launch.
    ///
    /// Called lazily on the first alert rather than at app start, so the
    /// permission prompt appears at a moment where its purpose is
    /// obvious, instead of as an unexplained dialog during onboarding.
    func requestAuthorizationIfNeeded() async {
        guard !hasRequestedAuthorization else { return }
        hasRequestedAuthorization = true

        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            // Permission denial is a legitimate user choice, not an error
            // state — the in-app banner still shows regardless, so the
            // feature degrades rather than breaks.
            print("SystemStressNotifier: authorization not granted — \(error.localizedDescription)")
        }
    }

    func deliver(_ alert: StressAlert) async {
        await requestAuthorizationIfNeeded()

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized ||
              settings.authorizationStatus == .provisional else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        // No sound for rising-trend nudges: a chime is itself a startle
        // response, which is the opposite of what a stress alert should
        // produce. Recovery notes are quiet for the same reason.
        content.sound = nil

        let request = UNNotificationRequest(
            identifier: alert.id.uuidString,
            content: content,
            trigger: nil  // deliver immediately
        )

        do {
            try await center.add(request)
        } catch {
            print("SystemStressNotifier: failed to deliver — \(error.localizedDescription)")
        }
    }
}

// MARK: - No-Op Implementation (previews, tests, notifications disabled)

final class NoOpStressNotifier: StressNotifying {
    private(set) var delivered: [StressAlert] = []

    func requestAuthorizationIfNeeded() async {}

    func deliver(_ alert: StressAlert) async {
        delivered.append(alert)
    }
}
