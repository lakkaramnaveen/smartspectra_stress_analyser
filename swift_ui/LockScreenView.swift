import SwiftUI

/// Full-screen gate shown before any camera/vitals UI is reachable.
///
/// Authentication is triggered automatically on appear — a lock screen
/// nobody has to remember to tap through is the only kind that reliably
/// stays in front of the sensitive content underneath it.
struct LockScreenView: View {
    let locking: AppLocking
    let onUnlock: () -> Void

    @State private var isAuthenticating = false
    @State private var statusMessage: String?
    @State private var isBlocked = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield")
                .font(.system(size: 56))
                .foregroundStyle(BrandColor.primaryBlue)

            Text("SmartSpectra Locked")
                .font(.title2.weight(.semibold))

            Text("Camera and vitals stay hidden until you unlock with Touch ID or your Mac password.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)

            if let statusMessage {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(isBlocked ? .red : .secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
            }

            Button(action: attemptUnlock) {
                if isAuthenticating {
                    ProgressView()
                        .controlSize(.small)
                        .frame(minWidth: 120)
                } else {
                    Text(isBlocked ? "Try Again" : "Unlock")
                        .frame(minWidth: 120)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isAuthenticating)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .task { attemptUnlock() }
    }

    private func attemptUnlock() {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        statusMessage = nil

        Task {
            let result = await locking.authenticate()
            isAuthenticating = false
            switch result {
            case .success:
                onUnlock()
            case .failure(let error):
                isBlocked = true
                statusMessage = error.errorDescription
            }
        }
    }
}
