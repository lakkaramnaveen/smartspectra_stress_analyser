import Foundation
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif

// MARK: - Queue Storage

protocol HealthSyncStoring {
    func loadQueue() -> [HealthSyncBatch]
    func saveQueue(_ batches: [HealthSyncBatch]) throws
}

final class FileHealthSyncStore: HealthSyncStoring {
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

        fileURL = directory.appendingPathComponent("health_export_queue.json")
    }

    func loadQueue() -> [HealthSyncBatch] {
        guard let data = try? Data(contentsOf: fileURL),
              let batches = try? decoder.decode([HealthSyncBatch].self, from: data) else {
            return []
        }
        return batches
    }

    func saveQueue(_ batches: [HealthSyncBatch]) throws {
        // Bounded even though batches are small — this is a queue meant
        // to be drained by export, not an indefinitely growing archive.
        let capped = Array(batches.suffix(500))
        let data = try encoder.encode(capped)
        try data.write(to: fileURL, options: .atomic)
    }
}

final class InMemoryHealthSyncStore: HealthSyncStoring {
    private var batches: [HealthSyncBatch]
    init(batches: [HealthSyncBatch] = []) { self.batches = batches }
    func loadQueue() -> [HealthSyncBatch] { batches }
    func saveQueue(_ batches: [HealthSyncBatch]) throws { self.batches = batches }
}

// MARK: - Export

/// Writes the queued batches to a user-chosen JSON file.
///
/// This is the actual, real thing this feature does: produce a portable
/// file containing correctly-mapped health data. It is not a sync, and
/// nothing here claims otherwise — see the platform note on
/// `HealthSyncView` for what would still be needed to get this into
/// Health for real.
enum HealthSyncExporter {

    static func json(for batches: [HealthSyncBatch]) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(batches)
    }

    #if os(macOS)
    @MainActor
    static func exportWithSavePanel(
        _ batches: [HealthSyncBatch],
        onComplete: @escaping (Bool) -> Void
    ) {
        guard !batches.isEmpty else {
            onComplete(false)
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "composure-health-export-\(dateStamp()).json"

        panel.begin { response in
            guard response == .OK, let url = panel.url, let data = json(for: batches) else {
                onComplete(false)
                return
            }
            do {
                try data.write(to: url, options: .atomic)
                onComplete(true)
            } catch {
                print("HealthSyncExporter: failed to write export — \(error.localizedDescription)")
                onComplete(false)
            }
        }
    }

    private static func dateStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return formatter.string(from: Date())
    }
    #endif
}
