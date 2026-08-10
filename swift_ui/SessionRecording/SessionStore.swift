import Foundation

// MARK: - Errors

enum SessionStoreError: LocalizedError {
    case notFound
    case ioFailure(Error)

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "Session recording not found."
        case .ioFailure(let error):
            return "Storage error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Protocol

/// Persists session recordings. Abstracted behind a protocol — exactly
/// like `CredentialStoring` elsewhere in this codebase — so callers
/// depend on behavior, not on disk I/O, and tests can inject an
/// in-memory fake instead of touching the filesystem.
protocol SessionStoring {
    func save(_ recording: SessionRecording) throws
    func loadSummaries() -> [SessionSummary]
    func load(id: UUID) throws -> SessionRecording
    func delete(id: UUID) throws
}

// MARK: - File-Based Implementation

/// Stores each recording as its own JSON file under Application Support,
/// plus a lightweight `index.json` of summaries.
///
/// Why not one big blob in `UserDefaults`: `UserDefaults` is meant for
/// small preferences, not an ever-growing session history, and has
/// practical size limits. Splitting into one file per recording means a
/// single corrupted or oversized file can't take down the whole history,
/// and the separate index lets the history list load instantly without
/// deserializing every snapshot array on every launch.
final class FileSessionStore: SessionStoring {
    private let fileManager = FileManager.default
    private let sessionsDirectory: URL
    private let indexURL: URL

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

    init(appSupportSubdirectory: String = "Composure/Sessions") {
        let base = fileManager
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? fileManager.temporaryDirectory

        sessionsDirectory = base.appendingPathComponent(appSupportSubdirectory, isDirectory: true)
        indexURL = sessionsDirectory.appendingPathComponent("index.json")

        try? fileManager.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
    }

    func save(_ recording: SessionRecording) throws {
        let fileURL = sessionsDirectory.appendingPathComponent("\(recording.id.uuidString).json")

        do {
            let data = try encoder.encode(recording)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw SessionStoreError.ioFailure(error)
        }

        var summaries = loadSummaries().filter { $0.id != recording.id }
        summaries.insert(recording.summary, at: 0)
        try writeIndex(summaries)
    }

    func loadSummaries() -> [SessionSummary] {
        guard let data = try? Data(contentsOf: indexURL),
              let summaries = try? decoder.decode([SessionSummary].self, from: data) else {
            return []
        }
        return summaries.sorted { $0.startedAt > $1.startedAt }
    }

    func load(id: UUID) throws -> SessionRecording {
        let fileURL = sessionsDirectory.appendingPathComponent("\(id.uuidString).json")
        guard let data = try? Data(contentsOf: fileURL) else {
            throw SessionStoreError.notFound
        }
        do {
            return try decoder.decode(SessionRecording.self, from: data)
        } catch {
            throw SessionStoreError.ioFailure(error)
        }
    }

    func delete(id: UUID) throws {
        let fileURL = sessionsDirectory.appendingPathComponent("\(id.uuidString).json")
        try? fileManager.removeItem(at: fileURL)

        let remaining = loadSummaries().filter { $0.id != id }
        try writeIndex(remaining)
    }

    private func writeIndex(_ summaries: [SessionSummary]) throws {
        do {
            let data = try encoder.encode(summaries)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            throw SessionStoreError.ioFailure(error)
        }
    }
}

// MARK: - In-Memory Implementation (for previews & unit tests)

final class InMemorySessionStore: SessionStoring {
    private var storage: [UUID: SessionRecording] = [:]

    func save(_ recording: SessionRecording) throws {
        storage[recording.id] = recording
    }

    func loadSummaries() -> [SessionSummary] {
        storage.values
            .map(\.summary)
            .sorted { $0.startedAt > $1.startedAt }
    }

    func load(id: UUID) throws -> SessionRecording {
        guard let recording = storage[id] else { throw SessionStoreError.notFound }
        return recording
    }

    func delete(id: UUID) throws {
        storage.removeValue(forKey: id)
    }
}
