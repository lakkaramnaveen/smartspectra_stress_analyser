import Foundation
import SwiftUI

/// A coarse, three-band summary — nothing finer than this ever leaves
/// the device through this feature.
///
/// This is a deliberately different design from `TherapistReportConfig`,
/// which includes weekly detail and the person's name because it's
/// going to their *own* clinician. This is meant for a pool the person
/// doesn't control the other end of, so the file itself carries nothing
/// more precise than a band, and never a name — not because a setting
/// says not to, but because there's nothing more precise to include.
enum StressBand: String, Sendable {
    case low, moderate, high

    static func classify(_ averageStress: Double) -> StressBand {
        switch averageStress {
        case ..<0.35: return .low
        case 0.35..<0.65: return .moderate
        default: return .high
        }
    }

    var label: String {
        switch self {
        case .low: return "Low"
        case .moderate: return "Moderate"
        case .high: return "High"
        }
    }

    var color: Color {
        switch self {
        case .low: return BrandColor.mint
        case .moderate: return BrandColor.lightBlue
        case .high: return BrandColor.amber
        }
    }
}

struct WellnessPulseConfig: Codable, Equatable, Sendable {
    /// Off by default, same as every other feature here that reaches
    /// beyond the person's own device.
    var isEnabled: Bool = false
}

/// The entire contents of an export. Deliberately this small — a period
/// label and a band, nothing else. No name, no raw score, no session
/// count, no timestamps.
struct WellnessPulseExport: Sendable {
    let periodLabel: String
    let band: StressBand
    let generatedAt: Date
}
