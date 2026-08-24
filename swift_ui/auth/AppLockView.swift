import SwiftUI

/// Full-screen lock, shown by `AppLockGateView` in place of
/// `RootSwitcherView` whenever `AppLockCoordinator.isUnlocked` is `false`.
///
/// Branches on `coordinator.isConfigured` exactly the way `RootSwitcherView`
/// branches on `profiles.activeProfile`: one view, two mutually exclusive
/// states, rather than a separate first-run screen elsewhere in the app
/// that could drift out of sync with this one.
struct AppLockView: View {
    @ObservedObject var coordinator: AppLockCoordinator

    @State private var passcode = ""
    @State private var confirmation = ""
    @State private var isConfirmingReset = false
    /// True only while `resetPasscode()`'s Touch ID / password prompt is
    /// in flight — disables the trigger so a second tap can't stack a
    /// second system auth prompt on top of the first.
    @State private var isAuthenticatingReset = false
    /// Same idea as `isAuthenticatingReset`, for the Touch ID unlock
    /// button rather than the reset flow.
    @State private var isAuthenticatingUnlock = false

    var body: some View {
        VStack(spacing: Spacing.xxl) {
            Spacer()

            VStack(spacing: 6) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 34))
                    .foregroundStyle(BrandColor.teal)
                Text(coordinator.isConfigured ? "Composure is locked" : "Set up a passcode")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                Text(coordinator.isConfigured
                     ? "Enter your passcode to continue."
                     : "Protects everyone's data on this Mac when you're away.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: Spacing.md) {
                if coordinator.isConfigured {
                    unlockFields
                } else {
                    setupFields
                }

                if !coordinator.errorMessage.isEmpty {
                    Text(coordinator.errorMessage)
                        .font(.caption)
                        .foregroundStyle(BrandColor.coral)
                }
            }
            .frame(maxWidth: 260)

            if coordinator.isConfigured {
                Button("Forgot passcode?") { isConfirmingReset = true }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                    .disabled(isAuthenticatingReset)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BrandColor.slate)
        .alert(
            "Reset your passcode?",
            isPresented: $isConfirmingReset
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Reset passcode", role: .destructive, action: requestReset)
        } message: {
            Text("You'll need to confirm with Touch ID or your Mac's password. Nobody's sessions, goals, or logs are affected — you'll just be asked to set a new passcode.")
        }
    }

    private var setupFields: some View {
        VStack(spacing: Spacing.sm) {
            SecureField("Passcode", text: $passcode)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submitSetup)

            SecureField("Confirm passcode", text: $confirmation)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submitSetup)

            Button("Set Passcode", action: submitSetup)
                .buttonStyle(.borderedProminent)
                .tint(BrandColor.primaryBlue)
                .disabled(passcode.isEmpty || confirmation.isEmpty)
                .frame(maxWidth: .infinity)
        }
    }

    private var unlockFields: some View {
        VStack(spacing: Spacing.sm) {
            SecureField("Passcode", text: $passcode)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submitUnlock)

            Button("Unlock", action: submitUnlock)
                .buttonStyle(.borderedProminent)
                .tint(BrandColor.primaryBlue)
                .disabled(passcode.isEmpty)
                .frame(maxWidth: .infinity)

            if coordinator.supportsBiometricUnlock {
                Button(action: requestBiometricUnlock) {
                    Label("Unlock with Touch ID", systemImage: "touchid")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isAuthenticatingUnlock)
            }
        }
    }

    private func submitSetup() {
        guard coordinator.setUp(passcode: passcode, confirmation: confirmation) else { return }
        passcode = ""
        confirmation = ""
    }

    private func submitUnlock() {
        coordinator.unlock(passcode: passcode)
        // Cleared either way: a wrong attempt shouldn't leave the failed
        // guess sitting in the field for a shoulder-surfer to read after
        // the error appears.
        passcode = ""
    }

    private func requestReset() {
        isAuthenticatingReset = true
        Task {
            let didReset = await coordinator.resetPasscode()
            isAuthenticatingReset = false
            if didReset {
                passcode = ""
                confirmation = ""
            }
        }
    }

    private func requestBiometricUnlock() {
        isAuthenticatingUnlock = true
        Task {
            await coordinator.unlockWithDeviceOwnerAuthentication()
            isAuthenticatingUnlock = false
        }
    }
}

#if DEBUG
#Preview("Setup") {
    AppLockView(coordinator: AppLockCoordinator(store: InMemoryAppLockCredentialStore()))
        .frame(width: 600, height: 500)
}

#Preview("Unlock") {
    AppLockView(coordinator: AppLockCoordinator(
        store: InMemoryAppLockCredentialStore(preconfiguredPasscode: "1234"),
        deviceAuthenticator: AlwaysSucceedsDeviceAuthenticator()
    ))
        .frame(width: 600, height: 500)
}
#endif
