import SwiftUI

/// Routine passcode change, opened from the Security card in
/// `SettingsView`. Distinct from the lock screen's "Forgot passcode?"
/// flow — this is for someone who still remembers their current passcode
/// and just wants a different one, so it asks for that instead of
/// reaching for Touch ID or the account password.
struct ChangePasscodeSheet: View {
    @ObservedObject var coordinator: AppLockCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var currentPasscode = ""
    @State private var newPasscode = ""
    @State private var confirmation = ""
    @State private var errorMessage = ""
    @State private var shakeTrigger: CGFloat = 0
    @FocusState private var currentPasscodeFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text("Change Passcode")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)

            SecureField("Current passcode", text: $currentPasscode)
                .textFieldStyle(.roundedBorder)
                .focused($currentPasscodeFocused)
                .shake(trigger: shakeTrigger)

            Divider().opacity(0.15)

            SecureField("New passcode", text: $newPasscode)
                .textFieldStyle(.roundedBorder)
            SecureField("Confirm new passcode", text: $confirmation)
                .textFieldStyle(.roundedBorder)

            Text("At least \(AppLockPolicy.minimumPasscodeLength) characters.")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.4))

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(BrandColor.coral)
            }

            Spacer(minLength: 0)

            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Save", action: save)
                    .buttonStyle(.borderedProminent)
                    .tint(BrandColor.primaryBlue)
                    .disabled(currentPasscode.isEmpty || newPasscode.isEmpty || confirmation.isEmpty)
            }
        }
        .padding(Spacing.xl)
        .frame(minWidth: 360)
        .background(BrandColor.slate)
        .onAppear { currentPasscodeFocused = true }
    }

    private func save() {
        do {
            try coordinator.changePasscode(current: currentPasscode, new: newPasscode, confirmation: confirmation)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription

            // Only the current-passcode field shakes for a wrong current
            // passcode; a mismatch between the two *new* fields is a
            // different mistake in a different place, so shaking this
            // field for it would misdirect the eye.
            if case ChangePasscodeError.incorrectCurrentPasscode = error {
                withAnimation(.default) { shakeTrigger += 1 }
                currentPasscode = ""
                currentPasscodeFocused = true
            }
        }
    }
}

#if DEBUG
#Preview {
    ChangePasscodeSheet(coordinator: AppLockCoordinator(
        store: InMemoryAppLockCredentialStore(preconfiguredPasscode: "1234"),
        deviceAuthenticator: AlwaysSucceedsDeviceAuthenticator()
    ))
}
#endif
