import Foundation

/// Names of two macOS Shortcuts the person has built themselves — one
/// for calming the space down, one for celebrating a recovery. Composure
/// never sees or configures what those Shortcuts actually do; it only
/// asks Shortcuts to run whichever one is named here. See the design
/// note on `HomeAutomationCoordinator` for why this indirection is the
/// real, working path rather than a compromise.
struct HomeAutomationConfig: Codable, Equatable, Sendable {
    var isEnabled: Bool = false
    var calmSceneShortcutName: String = ""
    var celebrateSceneShortcutName: String = ""
}
