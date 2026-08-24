import Foundation

protocol AppUsageStoring {
    func load() -> AppUsageState
    func save(_ state: AppUsageState) throws
}

final class FileAppUsageStore: AppUsageStoring {
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

        fileURL = directory.appendingPathComponent("app_usage.json")
    }

    func load() -> AppUsageState {
        guard let data = try? Data(contentsOf: fileURL),
              let state = try? decoder.decode(AppUsageState.self, from: data) else {
            return .initial
        }
        return state
    }

    func save(_ state: AppUsageState) throws {
        let data = try encoder.encode(state)
        try data.write(to: fileURL, options: .atomic)
    }
}

final class InMemoryAppUsageStore: AppUsageStoring {
    private var state: AppUsageState
    init(state: AppUsageState = .initial) { self.state = state }
    func load() -> AppUsageState { state }
    func save(_ state: AppUsageState) throws { self.state = state }
}
