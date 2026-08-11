import Foundation
import SwiftUI

// MARK: - Phase

enum FocusPhase: String, Codable, Equatable, Sendable {
    case focus
    case shortBreak
    case longBreak

    var label: String {
        switch self {
        case .focus: return "Focus"
        case .shortBreak: return "Break"
        case .longBreak: return "Long break"
        }
    }

    var icon: String {
        switch self {
        case .focus: return "target"
        case .shortBreak: return "cup.and.saucer"
        case .longBreak: return "figure.walk"
        }
    }

    var color: Color {
        switch self {
        case .focus: return BrandColor.primaryBlue
        case .shortBreak: return BrandColor.mint
        case .longBreak: return BrandColor.teal
        }
    }

    var isBreak: Bool { self != .focus }
}

// MARK: - Configuration

/// Timings for a Pomodoro-style cycle.
///
/// Configurable rather than hardcoded at 25/5/15. Those numbers are
/// conventional, not evidence-based — Cirillo picked 25 minutes because
/// that's what his kitchen timer did. Some people work better in 50s,
/// and anyone with attention difficulties may need shorter. Baking one
/// number into the app would present an arbitrary choice as a
/// prescription.
struct FocusConfiguration: Codable, Equatable, Sendable {
    var focusMinutes: Int
    var shortBreakMinutes: Int
    var longBreakMinutes: Int
    var roundsBeforeLongBreak: Int

    static let pomodoro = FocusConfiguration(
        focusMinutes: 25,
        shortBreakMinutes: 5,
        longBreakMinutes: 15,
        roundsBeforeLongBreak: 4
    )

    static let deepWork = FocusConfiguration(
        focusMinutes: 50,
        shortBreakMinutes: 10,
        longBreakMinutes: 20,
        roundsBeforeLongBreak: 3
    )

    static let short = FocusConfiguration(
        focusMinutes: 15,
        shortBreakMinutes: 5,
        longBreakMinutes: 15,
        roundsBeforeLongBreak: 4
    )

    static let presets: [(name: String, config: FocusConfiguration)] = [
        ("Short", .short),
        ("Pomodoro", .pomodoro),
        ("Deep work", .deepWork)
    ]

    /// Sensible bounds for the custom sliders.
    static let focusRange = 5...90
    static let breakRange = 1...30
    static let roundsRange = 2...8

    var sanitized: FocusConfiguration {
        FocusConfiguration(
            focusMinutes: focusMinutes.clamped(to: Self.focusRange),
            shortBreakMinutes: shortBreakMinutes.clamped(to: Self.breakRange),
            longBreakMinutes: longBreakMinutes.clamped(to: Self.breakRange),
            roundsBeforeLongBreak: roundsBeforeLongBreak.clamped(to: Self.roundsRange)
        )
    }

    func duration(for phase: FocusPhase) -> TimeInterval {
        switch phase {
        case .focus: return TimeInterval(focusMinutes * 60)
        case .shortBreak: return TimeInterval(shortBreakMinutes * 60)
        case .longBreak: return TimeInterval(longBreakMinutes * 60)
        }
    }
}

// MARK: - Stress Sample

/// Lightweight stress reading captured during a focus phase. Separate
/// from `SessionSnapshot` because focus tracking is coarser and shouldn't
/// depend on a recording session being active — focus mode works whether
/// or not the camera is running.
struct FocusStressSample: Equatable, Sendable {
    let timestamp: Date
    let score: Double
}

// MARK: - Summary

/// Post-phase result. Framed around what happened, not around pass/fail.
struct FocusSummary: Identifiable, Equatable, Sendable {
    let id = UUID()
    let phase: FocusPhase
    let plannedDuration: TimeInterval
    let actualDuration: TimeInterval
    let completedFully: Bool
    let roundNumber: Int

    let averageStress: Double?
    let peakStress: Double?
    /// Longest unbroken stretch at or above the elevated band.
    let sustainedHighStressSeconds: TimeInterval

    var hadStressData: Bool { averageStress != nil }

    /// Headline copy.
    ///
    /// Ending early is treated as a neutral outcome, not a failure.
    /// Someone who stops a focus block after eight minutes usually had a
    /// reason, and a productivity tool that scolds them is one they stop
    /// opening.
    var headline: String {
        if completedFully {
            return phase.isBreak ? "Break finished" : "Focus block complete"
        }
        return phase.isBreak ? "Break ended" : "Focus block ended early"
    }

    /// Whether the data suggests a longer break would help. Consulted at
    /// the phase boundary only — never used to interrupt an active
    /// block.
    var suggestsLongerBreak: Bool {
        guard phase == .focus, let peak = peakStress else { return false }
        return peak >= 0.75 || sustainedHighStressSeconds >= 300
    }

    var detail: String {
        guard let average = averageStress, let peak = peakStress else {
            return "\(DurationFormatter.mmss(actualDuration)) of \(DurationFormatter.mmss(plannedDuration)). No biometric data — monitoring wasn't running."
        }

        return "\(DurationFormatter.mmss(actualDuration)) · average stress \(percent(average)), peak \(percent(peak))."
    }

    private func percent(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }
}

// MARK: - Helpers

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
