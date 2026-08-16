import Foundation

// MARK: - Protocol

protocol CoachStoring {
    func load() -> [EffectivenessRecord]
    func save(_ records: [EffectivenessRecord]) throws
}

// MARK: - File

final class FileCoachStore: CoachStoring {
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

        fileURL = directory.appendingPathComponent("coach.json")
    }

    func load() -> [EffectivenessRecord] {
        guard let data = try? Data(contentsOf: fileURL),
              let records = try? decoder.decode([EffectivenessRecord].self, from: data) else {
            return []
        }
        return records
    }

    func save(_ records: [EffectivenessRecord]) throws {
        // Records accumulate roughly once per intervention, so this is
        // naturally low-volume, but cap it anyway rather than assume.
        let capped = Array(records.suffix(1000))
        let data = try encoder.encode(capped)
        try data.write(to: fileURL, options: .atomic)
    }
}

// MARK: - In-Memory

final class InMemoryCoachStore: CoachStoring {
    private var records: [EffectivenessRecord]

    init(records: [EffectivenessRecord] = []) { self.records = records }
    func load() -> [EffectivenessRecord] { records }
    func save(_ records: [EffectivenessRecord]) throws { self.records = records }
}
