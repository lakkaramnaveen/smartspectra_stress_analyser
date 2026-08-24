import Foundation
import SwiftUI

// MARK: - Store

protocol MeditationPreferencesStoring {
    func load() -> MeditationPreferences
    func save(_ preferences: MeditationPreferences) throws
}

final class FileMeditationPreferencesStore: MeditationPreferencesStoring {
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

        fileURL = directory.appendingPathComponent("meditation.json")
    }

    func load() -> MeditationPreferences {
        guard let data = try? Data(contentsOf: fileURL),
              let preferences = try? decoder.decode(MeditationPreferences.self, from: data) else {
            return .initial
        }
        return preferences
    }

    func save(_ preferences: MeditationPreferences) throws {
        let data = try encoder.encode(preferences)
        try data.write(to: fileURL, options: .atomic)
    }
}

final class InMemoryMeditationPreferencesStore: MeditationPreferencesStoring {
    private var preferences: MeditationPreferences

    init(preferences: MeditationPreferences = .initial) {
        self.preferences = preferences
    }

    func load() -> MeditationPreferences { preferences }
    func save(_ preferences: MeditationPreferences) throws { self.preferences = preferences }
}

// MARK: - Coordinator

@MainActor
final class MeditationCoordinator: ObservableObject {

    @Published private(set) var engine = MeditationSessionEngine()
    @Published private(set) var preferences: MeditationPreferences

    /// Set to present the player overlay.
    @Published var activeMeditation: Meditation?

    /// Result awaiting acknowledgement after a sitting ends.
    @Published var pendingSummary: MeditationSummary?

    private let store: MeditationPreferencesStoring
    private let analyzer: MeditationStressAnalyzer

    init(
        store: MeditationPreferencesStoring? = nil,
        analyzer: MeditationStressAnalyzer = MeditationStressAnalyzer()
    ) {
        let resolved = store ?? FileMeditationPreferencesStore()
        self.store = resolved
        self.preferences = resolved.load()
        self.analyzer = analyzer

        engine.onEnded = { [weak self] meditation, elapsed, completedFully, samples in
            self?.handleEnded(meditation, elapsed: elapsed, completedFully: completedFully, samples: samples)
        }
    }

    // MARK: Library

    var catalog: [Meditation] { Meditation.catalog }

    var favourites: [Meditation] {
        catalog.filter { preferences.isFavourite($0.id) }
    }

    func isFavourite(_ meditation: Meditation) -> Bool {
        preferences.isFavourite(meditation.id)
    }

    func toggleFavourite(_ meditation: Meditation) {
        if preferences.favouriteIDs.contains(meditation.id) {
            preferences.favouriteIDs.remove(meditation.id)
        } else {
            preferences.favouriteIDs.insert(meditation.id)
        }
        persist()
    }

    func completionCount(for meditation: Meditation) -> Int {
        preferences.completionCount(for: meditation.id)
    }

    // MARK: Sessions

    func begin(_ meditation: Meditation) {
        activeMeditation = meditation
        engine.start(meditation)
    }

    func end() {
        engine.stop()
    }

    func dismissPlayer() {
        engine.stop()
        activeMeditation = nil
    }

    func dismissSummary() {
        pendingSummary = nil
    }

    func ingest(stressScore: Double) {
        engine.ingest(stressScore: stressScore)
    }

    // MARK: Private

    private func handleEnded(
        _ meditation: Meditation,
        elapsed: TimeInterval,
        completedFully: Bool,
        samples: [Double]
    ) {
        let comparison = analyzer.compare(samples: samples)

        let completion = MeditationCompletion(
            meditationID: meditation.id,
            completedFully: completedFully,
            actualDuration: elapsed,
            stressBefore: comparison.before,
            stressAfter: comparison.after,
            sampleCount: comparison.sampleCount
        )

        preferences.completions.append(completion)
        persist()

        pendingSummary = MeditationSummary(
            meditation: meditation,
            elapsed: elapsed,
            completedFully: completedFully,
            comparison: comparison,
            totalCompletions: preferences.completionCount(for: meditation.id)
        )

        activeMeditation = nil
    }

    private func persist() {
        do {
            try store.save(preferences)
        } catch {
            print("MeditationCoordinator: failed to persist — \(error.localizedDescription)")
        }
    }
}

// MARK: - Summary

struct MeditationSummary: Identifiable, Equatable {
    let id = UUID()
    let meditation: Meditation
    let elapsed: TimeInterval
    let completedFully: Bool
    let comparison: MeditationStressComparison
    let totalCompletions: Int

    /// Ending early is neutral. Someone who sits for four minutes of a
    /// ten-minute meditation has meditated for four minutes, which is
    /// more than zero — copy that implies otherwise discourages the
    /// next attempt.
    var headline: String {
        completedFully ? "Sitting complete" : "Sitting ended"
    }

    var durationText: String {
        completedFully
            ? DurationFormatter.mmss(meditation.duration)
            : "\(DurationFormatter.mmss(elapsed)) of \(DurationFormatter.mmss(meditation.duration))"
    }
}
