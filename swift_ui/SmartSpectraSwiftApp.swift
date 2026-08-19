import SwiftUI

@main
struct SmartSpectraSwiftApp: App {
    @StateObject private var profiles = ProfileCoordinator()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootSwitcherView()
                .environmentObject(profiles)
                .environmentObject(appDelegate)
                .frame(minWidth: 1040, minHeight: 680)
        }
        .commands {
            // A single, non-reactive label ("Toggle Session" rather than
            // dynamically "Start"/"Stop") on purpose — `AppDelegate`
            // doesn't republish `objectWillChange` when the active
            // model's `isRunning` changes, so a label that tried to
            // track that state live would risk drifting stale. The
            // command itself always does the right thing regardless of
            // what its label says; only the label would have been at
            // risk, so removing the ambiguity there was the simpler and
            // more honest fix.
            CommandMenu("Session") {
                Button("Toggle Session") {
                    appDelegate.toggleSession()
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("Launch Balloon Hunt") {
                    appDelegate.launchGame()
                }
                .keyboardShortcut("g", modifiers: .command)
            }
        }
    }
}

// MARK: - Root Switcher

/// Branches between the profile picker and the live workspace.
///
/// This is the one place in the app that has to sit *above* `AppModel`
/// rather than compose into it, the way every other feature in this app
/// has. Which profile is active determines *how* `AppModel` gets
/// constructed — where every coordinator's files live — so that
/// decision has to be made before an `AppModel` exists, not from inside
/// one.
struct RootSwitcherView: View {
    @EnvironmentObject private var profiles: ProfileCoordinator

    var body: some View {
        if let active = profiles.activeProfile {
            ProfileScopedContentView(profile: active)
                // Binds this subtree's identity to the profile's id.
                // When the id changes, SwiftUI doesn't update the
                // existing `ProfileScopedContentView` in place — it
                // discards it, `@StateObject var model` included, and
                // builds a fresh one. That's the point: switching
                // profiles should tear the running `AppModel` down
                // entirely (camera engine, session state, everything)
                // rather than attempt to hot-swap a dozen coordinators'
                // underlying stores in place, possibly mid-session.
                .id(active.id)
        } else {
            ProfileSwitcherView(coordinator: profiles)
        }
    }
}

// MARK: - Profile-Scoped Workspace

/// Owns exactly one profile's `AppModel`, for as long as that profile
/// stays active. Constructed fresh each time `.id(active.id)` above
/// changes identity.
private struct ProfileScopedContentView: View {
    @EnvironmentObject private var appDelegate: AppDelegate
    @StateObject private var model: AppModel

    init(profile: UserProfile) {
        _model = StateObject(wrappedValue: AppModel(profile: profile))
    }

    var body: some View {
        ContentView()
            .environmentObject(model)
            .onAppear(perform: connectToAppDelegate)
            .task {
                if model.appPreferences.preferences.autoStartOnLaunch {
                    model.start()
                }
            }
            .onChange(of: model.focus.isActive) { _, isActive in
                guard model.appPreferences.preferences.alwaysOnTopDuringFocus else { return }
                NSApp.keyWindow?.level = isActive ? .floating : .normal
            }
    }

    /// Bridges this profile's live model to the app-wide menu-bar item
    /// and dock menu, both of which are constructed once at launch and
    /// outlive any single profile — see the design note on `AppDelegate`.
    private func connectToAppDelegate() {
        appDelegate.activeModel = model
        model.onStressTick = { [weak appDelegate] level, score in
            appDelegate?.updateStatusItem(level: level, score: score)
        }
        model.onSessionStopped = { [weak appDelegate] in
            appDelegate?.clearStatusItem()
        }
    }
}
