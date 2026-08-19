import Foundation
import SwiftUI

/// Appearance override for system chrome — the title bar, native panels
/// (`NSSavePanel`/`NSOpenPanel`, used throughout this app's export
/// features), and standard controls.
///
/// This does *not* reskin the app's own custom SwiftUI palette
/// (`BrandColor.slate` background, white-opacity text throughout every
/// feature built in this app) — that's a deliberate dark aesthetic
/// choice, the same design language apps like this typically use
/// regardless of system appearance, not something meant to follow
/// Light Mode. Making the custom palette itself appearance-adaptive
/// would mean converting `BrandColor`'s definition to dynamic,
/// resolution-time colors — a real, doable change, but one this file
/// deliberately doesn't attempt blind, since `BrandColor`'s actual
/// source predates this conversation and guessing at its full property
/// list risks silently dropping something already in use elsewhere.
enum AppearanceMode: String, Codable, CaseIterable, Sendable {
    case system, light, dark

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil  // nil restores following the system default
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

/// A curated set of accent colors, not an open color picker.
///
/// Deliberately not "any color you want": stress-level colors
/// (`StressLevel.color`, `RestQuality.color`, and similar) carry real
/// meaning throughout this app — calm reads as green-ish, critical as
/// warm — and letting someone recolor those arbitrarily would undermine
/// the at-a-glance status signaling the whole app relies on. This theme
/// only affects the *interactive accent* (buttons, active-tab
/// highlight, toggles) — the semantic status colors stay fixed
/// regardless of theme.
enum AccentTheme: String, Codable, CaseIterable, Sendable {
    case blue, teal, coral, violet

    var color: Color {
        switch self {
        case .blue: return BrandColor.primaryBlue
        case .teal: return BrandColor.teal
        case .coral: return Color(red: 0.95, green: 0.45, blue: 0.55)
        case .violet: return Color(red: 0.55, green: 0.45, blue: 0.95)
        }
    }

    var label: String {
        switch self {
        case .blue: return "Blue"
        case .teal: return "Teal"
        case .coral: return "Coral"
        case .violet: return "Violet"
        }
    }
}

struct AppPreferences: Codable, Equatable, Sendable {
    var appearanceMode: AppearanceMode = .system
    var accentTheme: AccentTheme = .blue
    var soundAlertsEnabled: Bool = false
    var dockBadgeEnabled: Bool = false
    var alwaysOnTopDuringFocus: Bool = true
    var autoStartOnLaunch: Bool = false
}
