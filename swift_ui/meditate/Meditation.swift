import Foundation
import SwiftUI

// MARK: - Category

enum MeditationCategory: String, Codable, CaseIterable, Sendable {
    case settling
    case bodyScan
    case breathAwareness
    case openAwareness

    var label: String {
        switch self {
        case .settling: return "Settling"
        case .bodyScan: return "Body scan"
        case .breathAwareness: return "Breath"
        case .openAwareness: return "Open awareness"
        }
    }

    var icon: String {
        switch self {
        case .settling: return "moon"
        case .bodyScan: return "figure.stand"
        case .breathAwareness: return "wind"
        case .openAwareness: return "sparkles"
        }
    }

    var color: Color {
        switch self {
        case .settling: return BrandColor.lightBlue
        case .bodyScan: return BrandColor.teal
        case .breathAwareness: return BrandColor.mint
        case .openAwareness: return BrandColor.primaryBlue
        }
    }
}

// MARK: - Cue

/// A single instruction shown at a point in the meditation.
///
/// Text cues rather than narration audio, by default. Recording or
/// licensing guided-meditation audio is a content project, not an
/// engineering one, and shipping a feature that requires assets you
/// don't have means shipping something broken. Text-cued meditations
/// work today with zero assets; `Meditation.audioFilename` exists so
/// narration can be layered on later without touching this structure.
struct MeditationCue: Codable, Equatable, Sendable, Identifiable {
    var id: String { "\(offset)-\(text.prefix(12))" }

    /// Seconds from the start of the meditation.
    let offset: TimeInterval
    let text: String

    /// Optional secondary line, shown smaller. Useful for a gentle
    /// elaboration that shouldn't compete with the main instruction.
    let subtext: String?

    init(offset: TimeInterval, text: String, subtext: String? = nil) {
        self.offset = offset
        self.text = text
        self.subtext = subtext
    }
}

// MARK: - Meditation

struct Meditation: Identifiable, Codable, Equatable, Sendable {
    let id: String              // stable; survives catalog edits
    let title: String
    let summary: String
    let category: MeditationCategory
    let duration: TimeInterval
    let cues: [MeditationCue]

    /// Optional narration track. When `nil` (the default for every
    /// built-in), the session runs text-cued and silent.
    let audioFilename: String?

    /// Whether to run the ambient breathing pacer alongside the cues.
    /// Breath-focused meditations use it; open-awareness ones
    /// deliberately don't, since pacing your breath is the opposite of
    /// letting it be.
    let includesBreathPacing: Bool

    /// Suggested pattern when `includesBreathPacing` is true.
    let breathPattern: BreathingPattern?

    var minutes: Int { Int((duration / 60).rounded()) }

    /// Cue active at a given elapsed time.
    func cue(at elapsed: TimeInterval) -> MeditationCue? {
        cues.last { $0.offset <= elapsed }
    }
}

// MARK: - Catalog

extension Meditation {

    /// Three minutes. The shortest useful unit — long enough to settle,
    /// short enough that "I don't have time" isn't true.
    static let threeMinuteSettle = Meditation(
        id: "med.settle.3",
        title: "Three-minute settle",
        summary: "A short pause to arrive. Good between tasks or before something demanding.",
        category: .settling,
        duration: 180,
        cues: [
            MeditationCue(offset: 0, text: "Settle into a comfortable position", subtext: "Eyes open or closed, whichever suits"),
            MeditationCue(offset: 20, text: "Notice where your body is in contact with the chair"),
            MeditationCue(offset: 50, text: "Let your attention rest on your breath", subtext: "No need to change it"),
            MeditationCue(offset: 90, text: "If your mind wanders, that's expected", subtext: "Notice it, and come back"),
            MeditationCue(offset: 130, text: "Take one deliberately slower breath"),
            MeditationCue(offset: 160, text: "Begin to widen your attention outward"),
            MeditationCue(offset: 172, text: "Whenever you're ready, carry on")
        ],
        audioFilename: nil,
        includesBreathPacing: false,
        breathPattern: nil
    )

    static let fiveMinuteBreath = Meditation(
        id: "med.breath.5",
        title: "Five minutes with the breath",
        summary: "Breath-paced, with a visual guide. A steady rhythm to follow when your thoughts are scattered.",
        category: .breathAwareness,
        duration: 300,
        cues: [
            MeditationCue(offset: 0, text: "Follow the circle with your breath", subtext: "In as it grows, out as it shrinks"),
            MeditationCue(offset: 45, text: "Let the rhythm do the work"),
            MeditationCue(offset: 120, text: "If the pace feels wrong, ignore it", subtext: "Your own breath is the better guide"),
            MeditationCue(offset: 200, text: "Notice how the exhale feels a little longer"),
            MeditationCue(offset: 270, text: "Let the pacing fall away"),
            MeditationCue(offset: 290, text: "Breathe however you like")
        ],
        audioFilename: nil,
        includesBreathPacing: true,
        breathPattern: BreathingPattern(inhale: 5.5, holdIn: 0, exhale: 5.5, holdOut: 0)
    )

    static let fiveMinuteBodyScan = Meditation(
        id: "med.body.5",
        title: "Five-minute body scan",
        summary: "Move attention slowly through the body. Useful when you've been in your head all day.",
        category: .bodyScan,
        duration: 300,
        cues: [
            MeditationCue(offset: 0, text: "Start with your feet", subtext: "Just notice — nothing to fix"),
            MeditationCue(offset: 40, text: "Move up through your legs"),
            MeditationCue(offset: 85, text: "Notice your lower back and hips"),
            MeditationCue(offset: 130, text: "Your stomach and chest", subtext: "Feel them move with the breath"),
            MeditationCue(offset: 180, text: "Your shoulders", subtext: "A common place to hold tension"),
            MeditationCue(offset: 220, text: "Your jaw, and around your eyes"),
            MeditationCue(offset: 260, text: "Take in the whole body at once"),
            MeditationCue(offset: 290, text: "Come back to the room when you're ready")
        ],
        audioFilename: nil,
        includesBreathPacing: false,
        breathPattern: nil
    )

    static let tenMinuteOpen = Meditation(
        id: "med.open.10",
        title: "Ten minutes of open awareness",
        summary: "Less structure. Sit with whatever comes up rather than directing attention anywhere in particular.",
        category: .openAwareness,
        duration: 600,
        cues: [
            MeditationCue(offset: 0, text: "Settle, and let your breath be as it is"),
            MeditationCue(offset: 60, text: "Notice sounds around you", subtext: "Without following any of them"),
            MeditationCue(offset: 180, text: "Notice thoughts arriving", subtext: "You don't have to do anything with them"),
            MeditationCue(offset: 330, text: "Notice how each one passes on its own"),
            MeditationCue(offset: 450, text: "Rest in whatever is here"),
            MeditationCue(offset: 540, text: "Begin to come back"),
            MeditationCue(offset: 585, text: "Take your time getting up")
        ],
        audioFilename: nil,
        includesBreathPacing: false,
        breathPattern: nil
    )

    static let tenMinuteSettle = Meditation(
        id: "med.settle.10",
        title: "Ten-minute wind-down",
        summary: "A longer settling practice with extended exhales. Suited to the end of the day.",
        category: .settling,
        duration: 600,
        cues: [
            MeditationCue(offset: 0, text: "Let the day start to set down"),
            MeditationCue(offset: 60, text: "Follow the pacing if it helps"),
            MeditationCue(offset: 180, text: "Longer out-breaths than in-breaths", subtext: "This is the part that slows things"),
            MeditationCue(offset: 330, text: "Nothing to solve right now"),
            MeditationCue(offset: 480, text: "Let the pacing go if you'd rather"),
            MeditationCue(offset: 555, text: "Rest here a while longer"),
            MeditationCue(offset: 585, text: "Come back gently")
        ],
        audioFilename: nil,
        includesBreathPacing: true,
        breathPattern: BreathingPattern(inhale: 4, holdIn: 0, exhale: 7, holdOut: 0)
    )

    static let catalog: [Meditation] = [
        .threeMinuteSettle,
        .fiveMinuteBreath,
        .fiveMinuteBodyScan,
        .tenMinuteSettle,
        .tenMinuteOpen
    ]

    static func meditation(id: String) -> Meditation? {
        catalog.first { $0.id == id }
    }
}

// MARK: - Completion Record

struct MeditationCompletion: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    let meditationID: String
    let completedAt: Date
    let completedFully: Bool
    let actualDuration: TimeInterval

    /// Mean stress over the opening window, if monitoring was running.
    let stressBefore: Double?
    /// Mean stress over the closing window.
    let stressAfter: Double?
    /// How many samples backed the comparison. Below a floor, the
    /// before/after difference isn't reported at all.
    let sampleCount: Int

    init(
        id: UUID = UUID(),
        meditationID: String,
        completedAt: Date = Date(),
        completedFully: Bool,
        actualDuration: TimeInterval,
        stressBefore: Double?,
        stressAfter: Double?,
        sampleCount: Int
    ) {
        self.id = id
        self.meditationID = meditationID
        self.completedAt = completedAt
        self.completedFully = completedFully
        self.actualDuration = actualDuration
        self.stressBefore = stressBefore
        self.stressAfter = stressAfter
        self.sampleCount = sampleCount
    }
}

// MARK: - Preferences

struct MeditationPreferences: Codable, Equatable, Sendable {
    var favouriteIDs: Set<String>
    var completions: [MeditationCompletion]

    static let initial = MeditationPreferences(favouriteIDs: [], completions: [])

    func completionCount(for id: String) -> Int {
        completions.filter { $0.meditationID == id && $0.completedFully }.count
    }

    var totalCompleted: Int {
        completions.filter(\.completedFully).count
    }

    func isFavourite(_ id: String) -> Bool {
        favouriteIDs.contains(id)
    }
}
