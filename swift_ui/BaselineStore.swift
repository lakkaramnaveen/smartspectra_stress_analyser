import Foundation
import os

private let logger = Logger(subsystem: "com.presagetech.smartspectra-swift-ui", category: "BaselineStore")

/// Persists the user's personal resting-vitals baseline. Abstracted
/// behind a protocol — same pattern as `CredentialStoring` and
/// `SessionStoring` — so `AppModel` depends on behavior, not disk I/O.
protocol BaselineStoring {
    func load() -> StressBaseline?
    func save(_ baseline: StressBaseline) throws
    func clear()
}

/// Stores the baseline as a single JSON file under Application Support.
///
/// Unlike the SmartSpectra API key, this isn't a credential — it's a
/// handful of resting-average numbers derived from the user's own vitals
/// — so plain-file storage is the right fit here, not Keychain. Matches
/// `FileSessionStore`'s approach (same `Composure` app-support folder) for
/// consistency.
final class BaselineStore: BaselineStoring {
    private let fileManager = FileManager.default
    private let fileURL: URL

    init(appSupportSubdirectory: String = "Composure") {
        let base = fileManager
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? fileManager.temporaryDirectory

        let folder = base.appendingPathComponent(appSupportSubdirectory, isDirectory: true)
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appendingPathComponent("baseline.json")
    }

    func load() -> StressBaseline? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(StressBaseline.self, from: data)
        } catch {
            logger.error("Failed to decode stored baseline: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func save(_ baseline: StressBaseline) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(baseline)
        try data.write(to: fileURL, options: .atomic)
    }

    func clear() {
        try? fileManager.removeItem(at: fileURL)
    }
}
