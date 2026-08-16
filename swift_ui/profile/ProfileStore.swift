import Foundation

// MARK: - Protocol

protocol ProfileStoring {
    func load() -> ProfilesState
    func save(_ state: ProfilesState) throws
}

// MARK: - File

/// Always resolves to the plain, unnamespaced `"Composure"` root —
/// deliberately never itself profile-scoped, since the list of profiles
/// (and which one was last active) has to be readable *before* any
/// profile has been chosen.
final class FileProfileStore: ProfileStoring {
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

        fileURL = directory.appendingPathComponent("profiles.json")
    }

    func load() -> ProfilesState {
        guard let data = try? Data(contentsOf: fileURL),
              let state = try? decoder.decode(ProfilesState.self, from: data),
              !state.profiles.isEmpty else {
            return .initial
        }
        return state
    }

    func save(_ state: ProfilesState) throws {
        let data = try encoder.encode(state)
        try data.write(to: fileURL, options: .atomic)
    }
}

// MARK: - In-Memory

final class InMemoryProfileStore: ProfileStoring {
    private var state: ProfilesState
    init(state: ProfilesState = .initial) { self.state = state }
    func load() -> ProfilesState { state }
    func save(_ state: ProfilesState) throws { self.state = state }
}
