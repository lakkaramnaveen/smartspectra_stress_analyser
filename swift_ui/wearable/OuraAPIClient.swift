import Foundation

// MARK: - Connection State

/// Everything needed to talk to Oura for one profile, persisted in
/// Keychain. Deliberately holds no client *secret* — see the note on
/// `OuraOAuthClient` for why.
struct OuraConnectionState: Codable, Equatable, Sendable {
    let clientID: String
    let redirectURI: String
    var accessToken: String?
    var expiresAt: Date?

    var isValid: Bool {
        guard let accessToken, !accessToken.isEmpty, let expiresAt else { return false }
        return expiresAt > Date()
    }
}

// MARK: - Response Models

/// Field names are the standard Oura v2 shape for this endpoint (`bpm`,
/// `source`, `timestamp`), but this is the one part of this file that
/// couldn't be confirmed against a literal example response during
/// research — worth a quick check against a real response the first
/// time this runs. Decoding failures here surface as
/// `OuraAPIError.decoding` rather than crashing, so a drifted field name
/// fails safely instead of taking down the fetch silently or violently.
struct OuraHeartRateRecord: Decodable, Sendable {
    let bpm: Double
    let source: String?
    let timestamp: Date
}

/// Multi-document Oura v2 endpoints wrap results in `{"data": [...],
/// "next_token": ...}`. Pagination via `next_token` isn't implemented —
/// a session's time window is short enough that a single page reliably
/// covers it, and adding cursor-following for a range this small would
/// be complexity with no real benefit here.
private struct OuraListResponse<T: Decodable>: Decodable {
    let data: [T]
}

// MARK: - Errors

enum OuraAPIError: LocalizedError {
    case unauthorized
    case membershipRequired
    case rateLimited
    case server(Int)
    case decoding

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Oura sign-in has expired — reconnect from this tab."
        case .membershipRequired:
            return "Reading data from Oura needs an active Oura membership."
        case .rateLimited:
            return "Too many requests to Oura right now — try again shortly."
        case .server(let code):
            return "Oura returned an unexpected error (\(code))."
        case .decoding:
            return "Couldn't read Oura's response."
        }
    }
}

// MARK: - Client

/// Thin wrapper around Oura's Cloud API v2, grounded against
/// `https://api.ouraring.com/v2/docs` and public integration guides
/// rather than built from memory: base URL, endpoint path, query
/// parameter names, the `{data: [...]}` response envelope, and the
/// documented HTTP error codes are all confirmed there as of this
/// writing. Oura's own API surface can change, the way any external
/// service's can — if requests start failing outright rather than
/// returning a normal error body, that's the first place to check.
struct OuraAPIClient: Sendable {
    private let baseURL = URL(string: "https://api.ouraring.com/v2/usercollection")!

    /// Heart-rate samples covering `start`...`end`.
    ///
    /// Oura's documentation states heart rate is recorded at five-minute
    /// increments, not continuously. A session lasting a few minutes may
    /// overlap only one or two Oura readings — which is exactly why the
    /// resulting comparison is a coarse, retrospective check, never a
    /// live one.
    func heartRateSamples(
        accessToken: String,
        start: Date,
        end: Date
    ) async throws -> [OuraHeartRateRecord] {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("heartrate"),
            resolvingAgainstBaseURL: false
        )!

        let formatter = ISO8601DateFormatter()
        components.queryItems = [
            URLQueryItem(name: "start_datetime", value: formatter.string(from: start)),
            URLQueryItem(name: "end_datetime", value: formatter.string(from: end))
        ]

        guard let url = components.url else { throw OuraAPIError.decoding }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else { throw OuraAPIError.decoding }

        switch http.statusCode {
        case 200: break
        case 401: throw OuraAPIError.unauthorized
        case 403: throw OuraAPIError.membershipRequired
        case 429: throw OuraAPIError.rateLimited
        default: throw OuraAPIError.server(http.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            return try decoder.decode(OuraListResponse<OuraHeartRateRecord>.self, from: data).data
        } catch {
            throw OuraAPIError.decoding
        }
    }
}
