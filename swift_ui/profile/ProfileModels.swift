import Foundation
import SwiftUI

// MARK: - Relationship Tag

/// A light, neutral categorisation used only for sorting and iconography
/// on the switcher and family dashboard — never for anything gendered or
/// role-specific. The actual identity is the free-text `name` a person
/// picks for themselves, exactly the way the feature's own examples
/// ("Mom", "Dad", "Teen") read as *names*, not fixed categories a family
/// structure has to fit into.
enum ProfileRelationship: String, Codable, CaseIterable, Sendable {
    case adult
    case teen
    case child
    case guest

    var label: String {
        switch self {
        case .adult: return "Adult"
        case .teen: return "Teen"
        case .child: return "Child"
        case .guest: return "Guest"
        }
    }

    var icon: String {
        switch self {
        case .adult: return "person.fill"
        case .teen: return "person.fill"
        case .child: return "figure.child"
        case .guest: return "person.fill.questionmark"
        }
    }
}

// MARK: - Colour Tag

/// Selectable avatar-ring colour, so profiles are quickly distinguishable
/// in the switcher without relying on reading the name every time.
enum ProfileColorTag: String, Codable, CaseIterable, Sendable {
    case teal, mint, coral, amber, primaryBlue, lightBlue

    var color: Color {
        switch self {
        case .teal: return BrandColor.teal
        case .mint: return BrandColor.mint
        case .coral: return BrandColor.coral
        case .amber: return BrandColor.amber
        case .primaryBlue: return BrandColor.primaryBlue
        case .lightBlue: return BrandColor.lightBlue
        }
    }
}

// MARK: - Profile

struct UserProfile: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var relationship: ProfileRelationship
    var colorTag: ProfileColorTag
    let createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        relationship: ProfileRelationship = .adult,
        colorTag: ProfileColorTag = .teal,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.relationship = relationship
        self.colorTag = colorTag
        self.createdAt = createdAt
    }

    /// Stable initial for the avatar circle when there's no picture.
    var initial: String {
        String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
    }

    /// Fixed identity for the profile every store already resolved to
    /// before profiles existed. Its `storageRoot` is deliberately the
    /// literal `"Composure"` path every `File*Store` in this codebase
    /// already defaults to — see `UserProfile.default`.
    static let defaultID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    /// The profile every existing single-user install already has,
    /// without any migration. `AppModel()` with no `profile` argument —
    /// every pre-existing call site and `#Preview` in this codebase —
    /// resolves to this profile and reads exactly where it always did.
    static let `default` = UserProfile(
        id: defaultID,
        name: "Me",
        relationship: .adult,
        colorTag: .teal,
        createdAt: Date(timeIntervalSince1970: 0)
    )

    /// The on-disk subdirectory (under Application Support) every
    /// coordinator's store for this profile resolves under.
    ///
    /// The default profile maps to the bare `"Composure"` root — the
    /// same path every store's own default already pointed at — so nothing
    /// needs to move for someone who never creates a second profile.
    /// Every other profile gets its own sibling folder, keeping each
    /// family member's files — and only their files — inside it.
    var storageRoot: String {
        id == UserProfile.defaultID ? "Composure" : "Composure/Profiles/\(id.uuidString)"
    }
}

// MARK: - Persisted State

/// Everything `ProfileStoring` persists, in one blob — same convention
/// as `GoalsState`.
struct ProfilesState: Codable, Equatable, Sendable {
    var profiles: [UserProfile]
    var activeProfileID: UUID?

    static let initial = ProfilesState(
        profiles: [.default],
        activeProfileID: UserProfile.defaultID
    )
}
