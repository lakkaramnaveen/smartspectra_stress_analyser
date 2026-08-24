import Foundation
import AppKit
import SwiftUI

/// Owns app-shell preferences and the small set of AppKit side effects
/// they drive: `NSApp.appearance`, the dock tile badge, and window
/// level. Everything here is local UI/UX preference — none of it
/// touches biometric data, so unlike most of this app's opt-in
/// features, these default to whatever's most useful rather than
/// defaulting off.
@MainActor
final class AppPreferencesCoordinator: ObservableObject {

    @Published var preferences: AppPreferences {
        didSet { applySideEffects() }
    }

    private let store: AppPreferencesStoring

    init(store: AppPreferencesStoring? = nil) {
        let resolved = store ?? FileAppPreferencesStore()
        self.store = resolved
        self.preferences = resolved.load()
    }

    /// Called once after launch, since the dock/appearance side effects
    /// need `NSApp` to be fully up, which isn't guaranteed at `init`
    /// time for a SwiftUI `App`.
    func applyOnLaunch() {
        applySideEffects()
    }

    private func applySideEffects() {
        NSApp.appearance = preferences.appearanceMode.nsAppearance

        if !preferences.dockBadgeEnabled {
            NSApp.dockTile.badgeLabel = nil
        }

        try? store.save(preferences)
    }

    /// Called from `AppModel` on every stress update — mirrors how
    /// every other lightweight side-effect coordinator in this app is
    /// fed. A single dock badge glyph, not stored biometric data, so
    /// this needs none of the consent machinery the actual data
    /// features use.
    func updateDockBadge(for level: StressLevel) {
        guard preferences.dockBadgeEnabled else { return }
        NSApp.dockTile.badgeLabel = level.dockBadgeGlyph
    }

    /// Called when a session stops, so the badge doesn't keep showing a
    /// reading from a session that's no longer running.
    func clearDockBadge() {
        NSApp.dockTile.badgeLabel = nil
    }
}

// MARK: - Store

protocol AppPreferencesStoring {
    func load() -> AppPreferences
    func save(_ preferences: AppPreferences) throws
}

final class FileAppPreferencesStore: AppPreferencesStoring {
    private let fileURL: URL

    init(appSupportSubdirectory: String = "Composure") {
        let fileManager = FileManager.default
        let base = fileManager
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? fileManager.temporaryDirectory
        let directory = base.appendingPathComponent(appSupportSubdirectory, isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("app_preferences.json")
    }

    func load() -> AppPreferences {
        guard let data = try? Data(contentsOf: fileURL),
              let preferences = try? JSONDecoder().decode(AppPreferences.self, from: data) else {
            return AppPreferences()
        }
        return preferences
    }

    func save(_ preferences: AppPreferences) throws {
        let data = try JSONEncoder().encode(preferences)
        try data.write(to: fileURL, options: .atomic)
    }
}

final class InMemoryAppPreferencesStore: AppPreferencesStoring {
    private var preferences = AppPreferences()
    func load() -> AppPreferences { preferences }
    func save(_ preferences: AppPreferences) throws { self.preferences = preferences }
}

// MARK: - Dock badge glyph

extension StressLevel {
    /// A short glyph, not a number — the dock badge is meant to be
    /// glanceable, not a precise readout.
    var dockBadgeGlyph: String {
        switch self {
        case .calm: return "●"
        case .moderate: return "●"
        case .elevated: return "▲"
        case .critical: return "!"
        }
    }
}
