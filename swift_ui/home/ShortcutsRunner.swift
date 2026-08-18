import Foundation

/// Runs a named macOS Shortcut via the system `shortcuts` command-line
/// tool.
///
/// ## Why this, and not `HomeKit.framework` directly
///
/// HomeKit *does* exist as a macOS framework — this isn't the
/// HealthKit/WatchConnectivity situation of a framework that's absent
/// from the platform entirely. But third-party access to it requires
/// the `com.apple.developer.homekit` entitlement, and Apple restricts
/// that entitlement to development-signed builds and Mac App Store
/// distribution — it cannot be included in a Developer ID provisioning
/// profile at all. A Developer ID build (which describes this project:
/// it links Homebrew libraries by absolute path, the opposite of what
/// the App Store accepts) would pass Gatekeeper and launch fine, but
/// `HMHomeManager` would simply report zero homes — not a bug to work
/// around, a deliberate platform restriction. Real-world reports from
/// developers who *did* get the entitlement also indicate `HMHomeManager`
/// effectively requires the app to be Mac Catalyst, not native
/// AppKit/SwiftUI-for-Mac — which would mean rebuilding this entire
/// project on a different app architecture, not adding a feature to it.
///
/// The `shortcuts` CLI needs no entitlement at all — it's a standard
/// system tool, and the Shortcuts app itself already has whatever
/// access it needs to control HomeKit scenes, since Apple's own apps
/// aren't subject to the third-party restriction above. So the actual,
/// working path is: the person builds their own Shortcut (a "Calm the
/// living room" scene, say) once, in the Shortcuts app, and Composure
/// simply asks the system to run it by name.
enum ShortcutsRunner {
    static func run(_ shortcutName: String) {
        let trimmed = shortcutName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["run", trimmed]

        do {
            try process.run()
        } catch {
            print("ShortcutsRunner: failed to run '\(trimmed)' — \(error.localizedDescription)")
        }
    }
}
