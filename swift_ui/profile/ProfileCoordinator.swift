import Foundation
import SwiftUI

/// Owns the list of family profiles and which one is active.
///
/// Deliberately independent of `AppModel` — it has to be, since which
/// profile is active determines how `AppModel` itself gets constructed
/// (see the note on `AppModel.init`). This coordinator lives at the app
/// entry point, one layer above everything else in the app.
@MainActor
final class ProfileCoordinator: ObservableObject {

    @Published private(set) var profiles: [UserProfile]
    @Published private(set) var activeProfile: UserProfile?

    private let store: ProfileStoring

    init(store: ProfileStoring? = nil) {
        let resolved = store ?? FileProfileStore()
        self.store = resolved

        let state = resolved.load()
        self.profiles = state.profiles
        self.activeProfile = state.profiles.first { $0.id == state.activeProfileID } ?? state.profiles.first
    }

    // MARK: - Selection

    /// Makes `profile` active. Persisted immediately, so relaunching the
    /// app returns to whoever was last selected rather than always
    /// showing the switcher.
    func select(_ profile: UserProfile) {
        activeProfile = profile
        persist()
    }

    /// Returns to the switcher without changing who was last active on
    /// disk — the persisted selection only updates via `select`, so this
    /// is a purely in-memory "show me the picker" action, not a logout.
    func requestSwitch() {
        activeProfile = nil
    }

    // MARK: - Management

    @discardableResult
    func createProfile(
        name: String,
        relationship: ProfileRelationship = .adult,
        colorTag: ProfileColorTag = .teal
    ) -> UserProfile {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let profile = UserProfile(
            name: trimmed.isEmpty ? "New profile" : trimmed,
            relationship: relationship,
            colorTag: colorTag
        )
        profiles.append(profile)
        persist()
        return profile
    }

    func rename(_ profile: UserProfile, to name: String) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        profiles[index].name = trimmed
        if activeProfile?.id == profile.id { activeProfile = profiles[index] }
        persist()
    }

    func updateAppearance(_ profile: UserProfile, relationship: ProfileRelationship, colorTag: ProfileColorTag) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[index].relationship = relationship
        profiles[index].colorTag = colorTag
        if activeProfile?.id == profile.id { activeProfile = profiles[index] }
        persist()
    }

    /// Whether `profile` can be removed from the list at all. The
    /// default profile can't be deleted — there always needs to be
    /// somewhere for the app to land if every custom profile is gone.
    func canDelete(_ profile: UserProfile) -> Bool {
        profile.id != UserProfile.defaultID
    }

    /// Removes a profile from the switcher. Deliberately does **not**
    /// touch its on-disk data — see `permanentlyDeleteData(for:)` for
    /// why that's kept as a separate, explicitly-confirmed action rather
    /// than bundled into what looks like a routine list edit.
    func remove(_ profile: UserProfile) {
        guard canDelete(profile) else { return }
        profiles.removeAll { $0.id == profile.id }
        if activeProfile?.id == profile.id {
            activeProfile = profiles.first
        }
        persist()
    }

    /// Deletes everything this profile ever stored — every session,
    /// every goal, every log — with no way back.
    ///
    /// Kept separate from `remove(_:)` on purpose. Removing someone from
    /// the switcher list is a low-stakes, reversible-feeling edit (add
    /// them back, nothing was lost); actually erasing a family member's
    /// wellness history is not, and the two shouldn't share one button.
    /// The view calling this is responsible for getting an explicit,
    /// unambiguous confirmation first — this method itself does not ask.
    func permanentlyDeleteData(for profile: UserProfile) throws {
        guard canDelete(profile) else { return }

        let fileManager = FileManager.default
        guard let base = fileManager
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first else { return }

        let directory = base.appendingPathComponent(profile.storageRoot, isDirectory: true)
        if fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }
    }

    // MARK: - Private

    private func persist() {
        let state = ProfilesState(profiles: profiles, activeProfileID: activeProfile?.id)
        try? store.save(state)
    }
}
