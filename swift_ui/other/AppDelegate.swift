import AppKit
import SwiftUI

/// Owns the AppKit chrome that exists above any single profile's
/// lifetime: the dock menu and the menu-bar status item.
///
/// Constructed once at launch via `@NSApplicationDelegateAdaptor` in
/// `SmartSpectraSwiftApp`. It holds a *weak* reference to whichever
/// profile's `AppModel` is currently active — set by
/// `ProfileScopedContentView` each time a profile is selected, and
/// automatically `nil` again once that model is torn down on a profile
/// switch, since nothing else holds a strong reference to it.
///
/// `ObservableObject` conformance here isn't for reactive UI updates —
/// it's what lets `@NSApplicationDelegateAdaptor` inject this into the
/// SwiftUI environment so `ProfileScopedContentView` can reach it via
/// `@EnvironmentObject`.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {

    weak var activeModel: AppModel?

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.title = "●"
        item.button?.action = #selector(toggleStatusPopover)
        item.button?.target = self
        statusItem = item

        let newPopover = NSPopover()
        newPopover.behavior = .transient
        popover = newPopover
    }

    // MARK: - Dock Menu

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()

        let toggleTitle = (activeModel?.isRunning ?? false) ? "Stop Session" : "Start Session"
        let toggleItem = NSMenuItem(title: toggleTitle, action: #selector(toggleSession), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)

        let gameItem = NSMenuItem(title: "Launch Balloon Hunt", action: #selector(launchGame), keyEquivalent: "")
        gameItem.target = self
        gameItem.isEnabled = activeModel?.isRunning ?? false
        menu.addItem(gameItem)

        return menu
    }

    // MARK: - Shared actions
    //
    // Reused by both the dock menu above and the `.commands` keyboard
    // shortcuts wired in `SmartSpectraSwiftApp` — one definition of
    // "start/stop the active session," not two.

    @objc func toggleSession() {
        guard let model = activeModel else { return }
        if model.isRunning {
            model.stop()
        } else {
            model.start()
        }
    }

    @objc func launchGame() {
        guard let model = activeModel, model.isRunning else { return }
        model.startGame()
    }

    // MARK: - Status Item

    /// Called from `AppModel.onStressTick` on every stress update, so
    /// the menu-bar title reflects live state without the status item
    /// needing to observe an `ObservableObject` whose identity changes
    /// every time the active profile switches.
    func updateStatusItem(level: StressLevel, score: Double) {
        statusItem?.button?.title = "\(level.dockBadgeGlyph) \(Int(score * 100))%"
    }

    func clearStatusItem() {
        statusItem?.button?.title = "●"
    }

    @objc private func toggleStatusPopover() {
        guard let button = statusItem?.button, let popover else { return }

        if popover.isShown {
            popover.performClose(nil)
            return
        }

        // Rebuilt fresh each time the popover opens, rather than kept
        // continuously live while showing — a menu-bar dropdown is
        // opened, glanced at, and closed in a couple of seconds, and
        // that's a reasonable trade against wiring a full reactive
        // bridge across the profile-switch boundary for something this
        // short-lived.
        let snapshot = StatusBarSnapshot(
            stressLevel: activeModel?.stressLevel ?? .calm,
            stressScore: activeModel?.stressScore ?? 0,
            isRunning: activeModel?.isRunning ?? false
        )
        popover.contentSize = NSSize(width: 220, height: 100)
        popover.contentViewController = NSHostingController(rootView: StatusBarSummaryView(snapshot: snapshot))
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
}

// MARK: - Popover Content

private struct StatusBarSnapshot {
    let stressLevel: StressLevel
    let stressScore: Double
    let isRunning: Bool
}

private struct StatusBarSummaryView: View {
    let snapshot: StatusBarSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Composure").font(.headline)

            if snapshot.isRunning {
                HStack(spacing: 6) {
                    Circle().fill(snapshot.stressLevel.color).frame(width: 8, height: 8)
                    Text(snapshot.stressLevel.label)
                    Spacer()
                    Text("\(Int(snapshot.stressScore * 100))%")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No session running")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(width: 220)
    }
}
