import Foundation

// MARK: - Protocol

/// Persists goals, unlocks, streak, and records.
///
/// Protocol-backed like `SessionStoring` and `CredentialStoring`, so the
/// coordinator depends on behaviour rather than the filesystem and tests
/// can run against an in-memory implementation.
protocol GoalsStoring {
    func load() -> GoalsState
    func save(_ state: GoalsState) throws
}

// MARK: - File Implementation

final class FileGoalsStore: GoalsStoring {
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

        fileURL = directory.appendingPathComponent("goals.json")
    }

    func load() -> GoalsState {
        guard let data = try? Data(contentsOf: fileURL),
              var state = try? decoder.decode(GoalsState.self, from: data) else {
            return .initial
        }

        // A user who somehow ends up with zero goals would have an empty,
        // inert dashboard with no way back. Restoring defaults is a
        // kinder failure mode than an empty screen.
        if state.goals.isEmpty {
            state.goals = Goal.defaultGoals
        }

        return state
    }

    func save(_ state: GoalsState) throws {
        let data = try encoder.encode(state)
        try data.write(to: fileURL, options: .atomic)
    }
}

// MARK: - In-Memory Implementation

final class InMemoryGoalsStore: GoalsStoring {
    private var state: GoalsState

    init(state: GoalsState = .initial) {
        self.state = state
    }

    func load() -> GoalsState { state }

    func save(_ state: GoalsState) throws { self.state = state }
}
