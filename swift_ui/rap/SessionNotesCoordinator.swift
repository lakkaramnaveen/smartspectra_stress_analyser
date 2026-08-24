import Foundation
import SwiftUI

// MARK: - Store

protocol SessionNoteStoring {
    func load() -> [SessionNote]
    func save(_ notes: [SessionNote]) throws
}

final class FileSessionNoteStore: SessionNoteStoring {
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

        fileURL = directory.appendingPathComponent("session_notes.json")
    }

    func load() -> [SessionNote] {
        guard let data = try? Data(contentsOf: fileURL),
              let notes = try? decoder.decode([SessionNote].self, from: data) else {
            return []
        }
        return notes
    }

    func save(_ notes: [SessionNote]) throws {
        let data = try encoder.encode(notes)
        try data.write(to: fileURL, options: .atomic)
    }
}

final class InMemorySessionNoteStore: SessionNoteStoring {
    private var notes: [SessionNote]
    init(notes: [SessionNote] = []) { self.notes = notes }
    func load() -> [SessionNote] { notes }
    func save(_ notes: [SessionNote]) throws { self.notes = notes }
}

// MARK: - Coordinator

@MainActor
final class SessionNotesCoordinator: ObservableObject {
    @Published private(set) var notes: [SessionNote] = []

    private let store: SessionNoteStoring

    init(store: SessionNoteStoring? = nil) {
        let resolved = store ?? FileSessionNoteStore()
        self.store = resolved
        self.notes = resolved.load().sorted { $0.date > $1.date }
    }

    func add(text: String, date: Date = Date(), linkedSessionID: UUID? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        notes.insert(SessionNote(date: date, text: trimmed, linkedSessionID: linkedSessionID), at: 0)
        notes.sort { $0.date > $1.date }
        persist()
    }

    func update(_ note: SessionNote, text: String, date: Date) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        notes[index].text = trimmed
        notes[index].date = date
        notes.sort { $0.date > $1.date }
        persist()
    }

    func delete(_ note: SessionNote) {
        notes.removeAll { $0.id == note.id }
        persist()
    }

    private func persist() {
        do {
            try store.save(notes)
        } catch {
            print("SessionNotesCoordinator: failed to persist — \(error.localizedDescription)")
        }
    }
}
