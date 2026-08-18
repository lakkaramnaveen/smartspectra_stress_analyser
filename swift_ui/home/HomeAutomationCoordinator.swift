import Foundation
import SwiftUI

@MainActor
final class HomeAutomationCoordinator: ObservableObject {

    @Published var config: HomeAutomationConfig
    @Published private(set) var lastTriggeredAt: Date?
    @Published private(set) var lastTriggerLabel: String?

    private var policy = HomeAutomationPolicy()
    private let store: HomeAutomationStoring

    init(store: HomeAutomationStoring? = nil) {
        let resolved = store ?? FileHomeAutomationStore()
        self.store = resolved
        self.config = resolved.load()
    }

    func updateConfig(_ newConfig: HomeAutomationConfig) {
        config = newConfig
        try? store.save(newConfig)
    }

    /// Called on every stress update, mirroring how every other live
    /// coordinator is fed from `AppModel.recomputeDerivedState()`.
    /// No-ops entirely unless the person has explicitly enabled this —
    /// off by default, same as every feature in this app that reaches
    /// beyond the device itself, and more so here: a false-positive
    /// automation has a physical effect in someone's home, not just a
    /// data question.
    func ingest(stressScore: Double, hasSettled: Bool) {
        guard config.isEnabled else { return }
        guard let trigger = policy.ingest(stressScore: stressScore, hasSettled: hasSettled) else { return }

        switch trigger {
        case .calmScene:
            guard !config.calmSceneShortcutName.isEmpty else { return }
            ShortcutsRunner.run(config.calmSceneShortcutName)
            lastTriggerLabel = "Calm scene"
        case .celebrateScene:
            guard !config.celebrateSceneShortcutName.isEmpty else { return }
            ShortcutsRunner.run(config.celebrateSceneShortcutName)
            lastTriggerLabel = "Celebrate scene"
        }
        lastTriggeredAt = Date()
    }
}

// MARK: - Store

protocol HomeAutomationStoring {
    func load() -> HomeAutomationConfig
    func save(_ config: HomeAutomationConfig) throws
}

final class FileHomeAutomationStore: HomeAutomationStoring {
    private let fileURL: URL

    init(appSupportSubdirectory: String = "Composure") {
        let fileManager = FileManager.default
        let base = fileManager
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? fileManager.temporaryDirectory
        let directory = base.appendingPathComponent(appSupportSubdirectory, isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("home_automation.json")
    }

    func load() -> HomeAutomationConfig {
        guard let data = try? Data(contentsOf: fileURL),
              let config = try? JSONDecoder().decode(HomeAutomationConfig.self, from: data) else {
            return HomeAutomationConfig()
        }
        return config
    }

    func save(_ config: HomeAutomationConfig) throws {
        let data = try JSONEncoder().encode(config)
        try data.write(to: fileURL, options: .atomic)
    }
}

final class InMemoryHomeAutomationStore: HomeAutomationStoring {
    private var config = HomeAutomationConfig()
    func load() -> HomeAutomationConfig { config }
    func save(_ config: HomeAutomationConfig) throws { self.config = config }
}
