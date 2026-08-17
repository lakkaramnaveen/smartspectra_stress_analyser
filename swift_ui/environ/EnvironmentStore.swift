import Foundation

protocol EnvironmentStoring {
    func load() -> EnvironmentState
    func save(_ state: EnvironmentState) throws
}

final class FileEnvironmentStore: EnvironmentStoring {
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

        fileURL = directory.appendingPathComponent("environment.json")
    }

    func load() -> EnvironmentState {
        guard let data = try? Data(contentsOf: fileURL),
              let state = try? decoder.decode(EnvironmentState.self, from: data) else {
            return .initial
        }
        return state
    }

    func save(_ state: EnvironmentState) throws {
        let data = try encoder.encode(state)
        try data.write(to: fileURL, options: .atomic)
    }
}

final class InMemoryEnvironmentStore: EnvironmentStoring {
    private var state: EnvironmentState
    init(state: EnvironmentState = .initial) { self.state = state }
    func load() -> EnvironmentState { state }
    func save(_ state: EnvironmentState) throws { self.state = state }
}
