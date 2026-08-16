import SwiftUI

@main
struct SmartSpectraSwiftApp: App {
    @StateObject private var profiles = ProfileCoordinator()

    var body: some Scene {
        WindowGroup {
            RootSwitcherView()
                .environmentObject(profiles)
                .frame(minWidth: 1040, minHeight: 680)
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
    @StateObject private var model: AppModel

    init(profile: UserProfile) {
        _model = StateObject(wrappedValue: AppModel(profile: profile))
    }

    var body: some View {
        ContentView()
            .environmentObject(model)
    }
}
