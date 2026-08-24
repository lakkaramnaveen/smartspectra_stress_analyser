import SwiftUI

struct SettingsView: View {
    @ObservedObject var coordinator: AppPreferencesCoordinator
    // Not passed as a parameter, unlike `coordinator` above — `AppLockCoordinator`
    // lives above any single profile (see its own design note), so every
    // view in the tree already reaches it through the environment the
    // same way `ContentView` reaches `profiles`.
    @EnvironmentObject private var appLock: AppLockCoordinator

    @State private var isChangingPasscode = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                header
                appearanceCard
                themeNote
                behaviorCard
                shortcutsNote
                securityCard
            }
            .padding(Spacing.xl)
        }
        .sheet(isPresented: $isChangingPasscode) {
            ChangePasscodeSheet(coordinator: appLock)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Settings")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
            Text("App behavior and appearance")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    // MARK: - Appearance

    private var appearanceCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Appearance").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)

            Picker("", selection: Binding(
                get: { coordinator.preferences.appearanceMode },
                set: { coordinator.preferences.appearanceMode = $0 }
            )) {
                ForEach(AppearanceMode.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Divider().opacity(0.15)

            Text("Accent color").font(.caption).foregroundStyle(.white.opacity(0.7))
            HStack(spacing: Spacing.md) {
                ForEach(AccentTheme.allCases, id: \.self) { theme in
                    accentSwatch(theme)
                }
            }
        }
        .padding(Spacing.lg)
        .background(Color.white.opacity(0.04))
        .cornerRadius(12)
    }

    private func accentSwatch(_ theme: AccentTheme) -> some View {
        let isSelected = coordinator.preferences.accentTheme == theme
        return Button {
            coordinator.preferences.accentTheme = theme
        } label: {
            Circle()
                .fill(theme.color)
                .frame(width: 28, height: 28)
                .overlay(Circle().stroke(.white, lineWidth: isSelected ? 2 : 0))
        }
        .buttonStyle(.plain)
    }

    /// Stated plainly rather than left to be discovered by disappointment
    /// — this preference exists and works, but its reach is narrower
    /// than "every accent-colored element in the app," and that
    /// boundary is worth being upfront about.
    private var themeNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("About appearance and theming")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))

            Text("Appearance mode controls system chrome — the title bar and native panels — not this app's own dark palette, which is a deliberate design choice rather than something meant to follow Light Mode. The accent color is a curated set, not an open picker: stress-level colors throughout the app carry real meaning, so those stay fixed regardless of theme.")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.md)
        .background(Color.white.opacity(0.03))
        .cornerRadius(8)
    }

    // MARK: - Behavior

    private var behaviorCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Behavior").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)

            toggleRow(
                "Sound on stress alerts",
                get: \.soundAlertsEnabled
            )
            toggleRow(
                "Show stress level on the dock icon",
                get: \.dockBadgeEnabled
            )
            toggleRow(
                "Keep window on top during Focus blocks",
                get: \.alwaysOnTopDuringFocus
            )
            toggleRow(
                "Start a session automatically on launch",
                get: \.autoStartOnLaunch
            )
        }
        .padding(Spacing.lg)
        .background(Color.white.opacity(0.04))
        .cornerRadius(12)
    }

    private func toggleRow(_ label: String, get keyPath: WritableKeyPath<AppPreferences, Bool>) -> some View {
        Toggle(isOn: Binding(
            get: { coordinator.preferences[keyPath: keyPath] },
            set: { coordinator.preferences[keyPath: keyPath] = $0 }
        )) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
        }
        .toggleStyle(.switch)
        .tint(BrandColor.primaryBlue)
    }

    private var shortcutsNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Keyboard shortcuts")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))

            Text("⌘R starts or stops the current session. ⌘G launches Balloon Hunt while a session is running. Both are also in the app's menu bar under Session, where every shortcut is discoverable without memorizing this list.")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.md)
        .background(Color.white.opacity(0.03))
        .cornerRadius(8)
    }

    // MARK: - Security

    /// The app-lock passcode is a household setting, not a per-profile
    /// one (see `AppLockCoordinator`'s own design note) — same reasoning
    /// as the API key on the Controls tab — so this card lives in
    /// Settings rather than anywhere profile-scoped.
    private var securityCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Security").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)

            Toggle(isOn: $appLock.autoLockOnSystemSleep) {
                Text("Lock automatically when your Mac sleeps or locks")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
            }
            .toggleStyle(.switch)
            .tint(BrandColor.primaryBlue)

            Divider().opacity(0.15)

            HStack {
                Text("Passcode")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                Button("Change…") { isChangingPasscode = true }
                    .buttonStyle(.bordered)
                    .tint(BrandColor.primaryBlue)
            }

            Text("⌘L locks Composure immediately from the Session menu.")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.45))
        }
        .padding(Spacing.lg)
        .background(Color.white.opacity(0.04))
        .cornerRadius(12)
    }
}

#if DEBUG
#Preview {
    SettingsView(coordinator: AppPreferencesCoordinator(store: InMemoryAppPreferencesStore()))
        .environmentObject(AppLockCoordinator(store: InMemoryAppLockCredentialStore(preconfiguredPasscode: "1234")))
        .frame(width: 420, height: 700)
        .background(BrandColor.slate)
}
#endif
