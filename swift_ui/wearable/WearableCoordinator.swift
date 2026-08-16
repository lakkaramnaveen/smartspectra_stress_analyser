import Foundation
import SwiftUI

/// Owns wearable connections and runs post-session reconciliation.
///
/// Deliberately **pull-based and session-scoped**, never part of the
/// live per-tick fan-out every other coordinator participates in via
/// `AppModel.recomputeDerivedState()`. There's no live wearable feed to
/// join against — Oura has to be asked, and a Watch file has to be
/// imported — so the only thing that makes sense is running a
/// reconciliation once a session has a defined start and end.
@MainActor
final class WearableCoordinator: ObservableObject {

    @Published private(set) var isOuraConnected = false
    @Published private(set) var ouraExpiresAt: Date?
    @Published private(set) var isAuthorizing = false
    @Published private(set) var isFetching = false
    @Published private(set) var lastError: String?
    @Published private(set) var latestReconciliation: SessionReconciliation?
    @Published private(set) var importedWatchReadings: [WearableReading] = []

    private let credentialStore: OuraCredentialStoring
    private let oauthClient = OuraOAuthClient()
    private let apiClient = OuraAPIClient()
    private let fusionEngine = BiometricFusionEngine()

    private var connection: OuraConnectionState?

    init(credentialStore: OuraCredentialStoring? = nil) {
        // Nil-defaulted for the same reason every other coordinator is:
        // default-argument expressions evaluate non-isolated, and
        // `OuraOAuthClient` (constructed above as a stored property
        // default, not a parameter) is itself `@MainActor`.
        let resolved = credentialStore ?? KeychainOuraCredentialStore(profileID: UserProfile.defaultID)
        self.credentialStore = resolved
        self.connection = resolved.load()
        refreshConnectionState()
    }

    // MARK: - Oura connection

    /// Requires the user's own Oura developer-app registration —
    /// `clientID` and `redirectURI` they set up themselves, exactly the
    /// way the SmartSpectra API key already works. See the setup note in
    /// `WearableTabView` for what that involves.
    func connectOura(clientID: String, redirectURI: String) async {
        guard !clientID.isEmpty, !redirectURI.isEmpty else { return }

        isAuthorizing = true
        defer { isAuthorizing = false }
        lastError = nil

        do {
            let (token, expiresAt) = try await oauthClient.authorize(
                clientID: clientID,
                redirectURI: redirectURI
            )
            let state = OuraConnectionState(
                clientID: clientID,
                redirectURI: redirectURI,
                accessToken: token,
                expiresAt: expiresAt
            )
            connection = state
            try? credentialStore.save(state)
            refreshConnectionState()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func disconnectOura() {
        connection = nil
        credentialStore.clear()
        refreshConnectionState()
    }

    private func refreshConnectionState() {
        isOuraConnected = connection?.isValid ?? false
        ouraExpiresAt = connection?.expiresAt
    }

    // MARK: - Apple Watch (import bridge)

    func importWatchData() {
        AppleWatchImporter.importWithOpenPanel { [weak self] readings in
            self?.importedWatchReadings.append(contentsOf: readings)
        }
    }

    // MARK: - Reconciliation

    /// Fetches Oura heart-rate samples covering `session`'s window and
    /// reconciles them, plus any imported Watch readings in the same
    /// window, against that session's own camera-derived average.
    func reconcile(session: SessionRecording) async {
        guard let end = session.endedAt else { return }

        guard let cameraSummary = CameraHeartRateSummary.from(
            heartRates: session.snapshots.map(\.heartRate)
        ) else {
            // Too little camera data to compare against anything —
            // a normal outcome for a very short session, not a failure
            // worth surfacing as an error.
            return
        }

        let watchReadings = importedWatchReadings.filter {
            $0.timestamp >= session.startedAt && $0.timestamp <= end
        }

        var ouraReadings: [WearableReading] = []

        if isOuraConnected, let token = connection?.accessToken {
            isFetching = true
            lastError = nil
            do {
                let records = try await apiClient.heartRateSamples(
                    accessToken: token,
                    start: session.startedAt,
                    end: end
                )
                ouraReadings = records.map {
                    WearableReading(source: .oura, bpm: $0.bpm, timestamp: $0.timestamp, confidence: 0.9)
                }
            } catch {
                lastError = error.localizedDescription
            }
            isFetching = false
        }

        latestReconciliation = fusionEngine.reconcile(
            camera: cameraSummary,
            wearableReadings: ouraReadings + watchReadings
        )
    }
}
