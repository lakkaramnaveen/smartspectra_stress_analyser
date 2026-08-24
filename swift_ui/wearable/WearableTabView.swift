import SwiftUI

struct WearableTabView: View {
    @ObservedObject var coordinator: WearableCoordinator
    let sessionStore: SessionStoring

    @State private var clientID: String = ""
    @State private var redirectURI: String = "composure-oura://oauth-callback"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                header
                ouraCard
                watchCard
                reconciliationCard
                setupNote
            }
            .padding(Spacing.xl)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Wearables")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
            Text("Cross-check the camera's heart rate against a ring or watch")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    // MARK: - Oura

    private var ouraCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "circle.circle")
                    .foregroundStyle(BrandColor.primaryBlue)
                Text("Oura")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
                connectionBadge
            }

            if coordinator.isOuraConnected {
                if let expires = coordinator.ouraExpiresAt {
                    Text("Connected — expires \(expires.formatted(date: .abbreviated, time: .omitted)). Oura doesn't support silent renewal, so you'll reconnect then.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
                Button("Disconnect", role: .destructive) {
                    coordinator.disconnectOura()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    TextField("Client ID (from your Oura app registration)", text: $clientID)
                        .textFieldStyle(.roundedBorder)
                    TextField("Redirect URI", text: $redirectURI)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                }

                Button {
                    Task { await coordinator.connectOura(clientID: clientID, redirectURI: redirectURI) }
                } label: {
                    if coordinator.isAuthorizing {
                        ProgressView().controlSize(.small).frame(maxWidth: .infinity)
                    } else {
                        Text("Connect Oura")
                            .font(.callout.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(BrandColor.primaryBlue)
                .disabled(clientID.isEmpty || redirectURI.isEmpty || coordinator.isAuthorizing)
            }

            if let error = coordinator.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(BrandColor.coral)
            }
        }
        .padding(Spacing.lg)
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }

    private var connectionBadge: some View {
        Text(coordinator.isOuraConnected ? "Connected" : "Not connected")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(coordinator.isOuraConnected ? BrandColor.mint : .white.opacity(0.4))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                (coordinator.isOuraConnected ? BrandColor.mint : Color.white).opacity(0.12),
                in: Capsule()
            )
    }

    // MARK: - Watch

    /// No live connection, no "Connect" toggle — an import button is the
    /// whole feature, and the copy says why rather than leaving the
    /// asymmetry with Oura unexplained.
    private var watchCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "applewatch")
                    .foregroundStyle(BrandColor.teal)
                Text("Apple Watch")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text("\(coordinator.importedWatchReadings.count) imported")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
            }

            Text("This Mac can't talk to a paired Watch directly — that pairing exists between a Watch and an iPhone, not a Mac. If a companion iOS app exports readings in a compatible format, import them here.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)

            Button("Import from file…") {
                coordinator.importWatchData()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(Spacing.lg)
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }

    // MARK: - Reconciliation

    @ViewBuilder
    private var reconciliationCard: some View {
        if let reconciliation = coordinator.latestReconciliation {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    Text("Most recent session")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    if coordinator.isFetching {
                        ProgressView().controlSize(.mini)
                    }
                }

                Text(reconciliation.agreement.label)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(reconciliation.agreement.color)

                HStack(spacing: Spacing.lg) {
                    metric("Camera avg", String(format: "%.0f bpm", reconciliation.cameraAverageBPM))
                    if let blended = reconciliation.blendedEstimateBPM {
                        metric("Blended", String(format: "%.0f bpm", blended))
                    }
                    if let deviation = reconciliation.maxDeviationBPM {
                        metric("Largest gap", String(format: "%.0f bpm", deviation))
                    }
                }

                if !reconciliation.wearableReadings.isEmpty {
                    Text("Compared against \(reconciliation.wearableReadings.count) wearable reading\(reconciliation.wearableReadings.count == 1 ? "" : "s") from this session's window.")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .padding(Spacing.lg)
            .background(Color.white.opacity(0.04))
            .cornerRadius(12)
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
        }
    }

    // MARK: - Setup note

    private var setupNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Before this works")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))

            Text("Oura requires its own registered app — Personal Access Tokens were retired in December 2025. Register one at cloud.ouraring.com (self-serve, free, covers up to 10 users), set its redirect URI to match the one above, and add that same URI as a custom URL scheme in this app's target settings (URL Types) so macOS can hand the sign-in result back to Composure. Reading data also needs an active Oura membership.")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)

            Text("This never asks for or stores a client secret — see the note on OuraOAuthClient for why. That means no silent token refresh either: expect to reconnect roughly monthly.")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)

            Text("Oura's heart rate is recorded at five-minute increments, not continuously, and only syncs when the Oura app on your phone does. This is a coarse, after-the-fact cross-check — not a live second opinion running alongside your session.")
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
@MainActor
private func makeWearablePreviewCoordinator() -> WearableCoordinator {
    let coordinator = WearableCoordinator(credentialStore: InMemoryOuraCredentialStore())
    return coordinator
}

#Preview {
    WearableTabView(
        coordinator: makeWearablePreviewCoordinator(),
        sessionStore: InMemorySessionStore()
    )
    .frame(width: 420, height: 780)
    .background(BrandColor.slate)
}
#endif
