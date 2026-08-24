import Foundation

// MARK: - Protocol

/// Persists logged nights.
///
/// Protocol-backed like `SessionStoring` and `CredentialStoring`, so the
/// coordinator depends on behaviour rather than the filesystem and tests
/// run against an in-memory implementation.
protocol SleepStoring {
    func load() -> [SleepEntry]
    func save(_ entries: [SleepEntry]) throws
}

// MARK: - File

final class FileSleepStore: SleepStoring {
    private let fileURL: URL

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    init(appSupportSubdirectory: String = "Composure") {
        let fileManager = FileManager.default
        let base = fileManager
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? fileManager.temporaryDirectory

        let directory = base.appendingPathComponent(appSupportSubdirectory, isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        fileURL = directory.appendingPathComponent("sleep.json")
    }

    func load() -> [SleepEntry] {
        guard let data = try? Data(contentsOf: fileURL),
              let entries = try? decoder.decode([SleepEntry].self, from: data) else {
            return []
        }
        return entries.sorted { $0.forDay > $1.forDay }
    }

    func save(_ entries: [SleepEntry]) throws {
        let data = try encoder.encode(entries)
        try data.write(to: fileURL, options: .atomic)
    }
}

// MARK: - In-Memory

final class InMemorySleepStore: SleepStoring {
    private var entries: [SleepEntry]

    init(entries: [SleepEntry] = []) { self.entries = entries }

    func load() -> [SleepEntry] {
        entries.sorted { $0.forDay > $1.forDay }
    }

    func save(_ entries: [SleepEntry]) throws { self.entries = entries }
}
