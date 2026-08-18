import SwiftUI

struct HomeAutomationView: View {
    @ObservedObject var coordinator: HomeAutomationCoordinator

    @State private var calmName: String = ""
    @State private var celebrateName: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                header
                platformNote
                configCard
                safetyNote
            }
            .padding(Spacing.xl)
        }
        .onAppear {
            calmName = coordinator.config.calmSceneShortcutName
            celebrateName = coordinator.config.celebrateSceneShortcutName
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Home Automation")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
            Text("Trigger a Shortcut when stress runs high, or when you've recovered")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    private var platformNote: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "info.circle")
                    .foregroundStyle(BrandColor.amber)
                Text("Why this uses Shortcuts, not HomeKit directly")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
            }

            Text("HomeKit access requires an entitlement Apple restricts to development-signed and Mac App Store builds — it can't be included in the kind of build this project is. This works by asking the Shortcuts app to run an automation you've already built yourself, which needs no special entitlement at all.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)

            Text("Set this up once: build a Shortcut for each scene in the Shortcuts app (a HomeKit action, or anything else you'd like), then enter its exact name below.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.lg)
        .background(BrandColor.amber.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(BrandColor.amber.opacity(0.3), lineWidth: 1)
        )
        .cornerRadius(12)
    }

    private var configCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Toggle(isOn: Binding(
                get: { coordinator.config.isEnabled },
                set: { var c = coordinator.config; c.isEnabled = $0; coordinator.updateConfig(c) }
            )) {
                Text("Enable home automation")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .toggleStyle(.switch)
            .tint(BrandColor.primaryBlue)

            if coordinator.config.isEnabled {
                shortcutField(
                    label: "When stress stays high",
                    text: $calmName,
                    placeholder: "e.g. \"Calm the room\""
                ) {
                    var c = coordinator.config
                    c.calmSceneShortcutName = calmName
                    coordinator.updateConfig(c)
                }

                shortcutField(
                    label: "When you've recovered",
                    text: $celebrateName,
                    placeholder: "e.g. \"Brighten up\""
                ) {
                    var c = coordinator.config
                    c.celebrateSceneShortcutName = celebrateName
                    coordinator.updateConfig(c)
                }

                if let label = coordinator.lastTriggerLabel, let at = coordinator.lastTriggeredAt {
                    Text("Last triggered: \(label) at \(at.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
        }
        .padding(Spacing.lg)
        .background(Color.white.opacity(0.04))
        .cornerRadius(12)
    }

    private func shortcutField(
        label: String,
        text: Binding<String>,
        placeholder: String,
        onCommit: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .onSubmit(onCommit)
                .onChange(of: text.wrappedValue) { _, _ in onCommit() }
        }
    }

    private var safetyNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("About safety limits")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))

            Text("Composure never sees what your Shortcut actually does — it only asks the system to run it by name. Anything like \"don't set the thermostat below 65°\" has to be built into the Shortcut itself; there's nothing here for Composure to enforce that on. It also won't fire more than once every 10 minutes, and only after stress has stayed high for a sustained stretch — not on a single noisy reading — but the device-level limits are entirely your Shortcut's responsibility.")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.md)
        .background(Color.white.opacity(0.03))
        .cornerRadius(8)
    }
}

#if DEBUG
#Preview {
    HomeAutomationView(coordinator: HomeAutomationCoordinator(store: InMemoryHomeAutomationStore()))
        .frame(width: 420, height: 700)
        .background(BrandColor.slate)
}
#endif
