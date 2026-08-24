import Foundation
import AuthenticationServices
import AppKit

/// Runs Oura's "client-side only" OAuth2 flow — the implicit grant,
/// `response_type=token` — using `ASWebAuthenticationSession`, which
/// *is* available and idiomatic on macOS (unlike HealthKit or
/// WatchConnectivity; this framework genuinely works here).
///
/// ## Why this flow, and not the one with refresh tokens
///
/// Oura also documents a server-side Authorization Code flow that
/// supports refresh tokens for longer-lived access. It requires a
/// client *secret* to exchange the authorization code. Multiple
/// independent Oura integration guides are explicit that the secret
/// belongs on a backend and should never ship inside a client app — and
/// a native Mac app distributed to users has no backend of its own to
/// keep it on. Embedding a secret in every copy of this app would mean
/// every installation shares one exposed credential.
///
/// The client-side flow needs only a `client_id` — no secret exists to
/// protect. The cost, also disclosed to the user in `WearableTabView`,
/// is that these tokens expire in 30 days with no silent refresh:
/// reauthorizing periodically is the accepted trade for never holding a
/// secret at rest.
@MainActor
final class OuraOAuthClient: NSObject, ASWebAuthenticationPresentationContextProviding {

    enum OAuthError: LocalizedError {
        case userCancelled
        case invalidCallback
        case missingAccessToken

        var errorDescription: String? {
            switch self {
            case .userCancelled: return "Sign-in was cancelled."
            case .invalidCallback: return "Oura didn't return a valid response."
            case .missingAccessToken: return "No access token was included in Oura's response."
            }
        }
    }

    private var activeSession: ASWebAuthenticationSession?

    /// - Parameters:
    ///   - clientID: from the user's own Oura developer app registration
    ///     — see the setup note in `WearableTabView`. Self-registered
    ///     apps can connect up to 10 users before Oura requires approval,
    ///     comfortably covering personal or small-household use.
    ///   - redirectURI: must match a custom URL scheme registered in
    ///     this target's Info settings (URL Types) *and* the redirect
    ///     URI configured in the Oura app registration — the one piece
    ///     of this feature that needs a small Xcode project change
    ///     alongside the Swift files.
    func authorize(
        clientID: String,
        redirectURI: String,
        scope: String = "heartrate"
    ) async throws -> (accessToken: String, expiresAt: Date) {
        guard var components = URLComponents(string: "https://cloud.ouraring.com/oauth/authorize") else {
            throw OAuthError.invalidCallback
        }

        let state = UUID().uuidString
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "token"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "state", value: state)
        ]

        guard let authorizeURL = components.url,
              let scheme = URLComponents(string: redirectURI)?.scheme else {
            throw OAuthError.invalidCallback
        }

        let callbackURL = try await runSession(authorizeURL: authorizeURL, callbackScheme: scheme)
        return try parse(callbackURL: callbackURL, expectedState: state)
    }

    // MARK: - Private

    private func runSession(authorizeURL: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authorizeURL,
                callbackURLScheme: callbackScheme
            ) { url, error in
                if let error {
                    let nsError = error as NSError
                    let wasCancelled = nsError.domain == ASWebAuthenticationSessionError.errorDomain
                        && nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue
                    continuation.resume(throwing: wasCancelled ? OAuthError.userCancelled : error)
                    return
                }
                guard let url else {
                    continuation.resume(throwing: OAuthError.invalidCallback)
                    return
                }
                continuation.resume(returning: url)
            }

            session.presentationContextProvider = self
            // Ephemeral: doesn't share cookies with the user's regular
            // browser session or persist any of its own — each
            // authorization is a clean slate, which also means the user
            // will see Oura's login screen every time rather than
            // staying silently signed in across attempts.
            session.prefersEphemeralWebBrowserSession = true

            activeSession = session
            session.start()
        }
    }

    /// The access token comes back in the URL **fragment**
    /// (`#access_token=...`), not the query string — this is the
    /// implicit grant. `URLComponents.queryItems` only parses `?query`,
    /// so the fragment has to be split by hand.
    private func parse(callbackURL: URL, expectedState: String) throws -> (accessToken: String, expiresAt: Date) {
        guard let fragment = callbackURL.fragment else {
            throw OAuthError.invalidCallback
        }

        var params: [String: String] = [:]
        for pair in fragment.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            params[String(parts[0])] = String(parts[1]).removingPercentEncoding ?? String(parts[1])
        }

        guard params["state"] == expectedState else {
            throw OAuthError.invalidCallback
        }
        guard let accessToken = params["access_token"] else {
            throw OAuthError.missingAccessToken
        }

        let expiresIn = params["expires_in"].flatMap(Double.init) ?? (30 * 24 * 60 * 60)
        return (accessToken, Date().addingTimeInterval(expiresIn))
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor()
        }
    }
}
