import Foundation
import SwiftUI

// MARK: - Store

protocol BreathingPreferencesStoring {
    func load() -> BreathingPreferences
    func save(_ preferences: BreathingPreferences) throws
}

final class FileBreathingPreferencesStore: BreathingPreferencesStoring {
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

        fileURL = directory.appendingPathComponent("breathing.json")
    }

    func load() -> BreathingPreferences {
        guard let data = try? Data(contentsOf: fileURL),
              let preferences = try? decoder.decode(BreathingPreferences.self, from: data) else {
            return .initial
        }
        return preferences
    }

    func save(_ preferences: BreathingPreferences) throws {
        let data = try encoder.encode(preferences)
        try data.write(to: fileURL, options: .atomic)
    }
}

final class InMemoryBreathingPreferencesStore: BreathingPreferencesStoring {
    private var preferences: BreathingPreferences

    init(preferences: BreathingPreferences = .initial) {
        self.preferences = preferences
    }

    func load() -> BreathingPreferences { preferences }
    func save(_ preferences: BreathingPreferences) throws { self.preferences = preferences }
}

// MARK: - Coordinator

/// Owns technique selection, the custom-technique library, and
/// completion counts. `AppModel` composes this; the pacer view and the
/// library view both read from it.
@MainActor
final class BreathingCoordinator: ObservableObject {

    @Published private(set) var preferences: BreathingPreferences

    /// Set to trigger the pacer overlay from anywhere (library "Try it",
    /// a predictive alert, or the automatic stress threshold).
    @Published var activeTechnique: BreathingTechnique?

    /// Called when a technique is completed in full. Wired to
    /// `GoalsCoordinator.recordBreathingCompleted()` by `AppModel`.
    var onTechniqueCompleted: (() -> Void)?

    private let store: BreathingPreferencesStoring

    init(store: BreathingPreferencesStoring? = nil) {
        // Constructed in the body, not as a default argument —
        // default-argument expressions evaluate non-isolated and trip
        // `@MainActor` checking.
        let resolved = store ?? FileBreathingPreferencesStore()
        self.store = resolved
        self.preferences = resolved.load()
    }

    // MARK: Library

    var allTechniques: [BreathingTechnique] {
        BreathingTechnique.builtIn + preferences.customTechniques
    }

    var selectedTechnique: BreathingTechnique {
        allTechniques.first { $0.id == preferences.selectedTechniqueID }
            ?? .extendedExhale
    }

    func select(_ technique: BreathingTechnique) {
        preferences.selectedTechniqueID = technique.id
        persist()
    }

    func saveCustom(_ technique: BreathingTechnique) {
        let safe = technique.sanitized

        if let index = preferences.customTechniques.firstIndex(where: { $0.id == safe.id }) {
            preferences.customTechniques[index] = safe
        } else {
            preferences.customTechniques.append(safe)
        }

        preferences.selectedTechniqueID = safe.id
        persist()
    }

    func deleteCustom(_ technique: BreathingTechnique) {
        guard !technique.isBuiltIn else { return }
        preferences.customTechniques.removeAll { $0.id == technique.id }

        // Don't leave the selection pointing at something deleted.
        if preferences.selectedTechniqueID == technique.id {
            preferences.selectedTechniqueID = BreathingTechnique.extendedExhale.id
        }

        // Completion history is kept deliberately. Deleting a technique
        // shouldn't erase the record of having practised it.
        persist()
    }

    // MARK: Sessions

    func begin(_ technique: BreathingTechnique) {
        activeTechnique = technique.sanitized
    }

    func beginSelected() {
        begin(selectedTechnique)
    }

    func dismissActive() {
        activeTechnique = nil
    }

    /// Records a *completed* technique. Called by the engine's
    /// `onCompleted` callback only, never on early exit.
    func recordCompletion(of technique: BreathingTechnique) {
        if let index = preferences.completions.firstIndex(where: { $0.techniqueID == technique.id }) {
            preferences.completions[index].completedCount += 1
            preferences.completions[index].lastCompletedAt = Date()
        } else {
            preferences.completions.append(
                TechniqueCompletion(
                    techniqueID: technique.id,
                    completedCount: 1,
                    lastCompletedAt: Date()
                )
            )
        }

        persist()
        onTechniqueCompleted?()
    }

    func completionCount(for technique: BreathingTechnique) -> Int {
        preferences.completionCount(for: technique.id)
    }

    // MARK: Private

    private func persist() {
        do {
            try store.save(preferences)
        } catch {
            print("BreathingCoordinator: failed to persist — \(error.localizedDescription)")
        }
    }
}
