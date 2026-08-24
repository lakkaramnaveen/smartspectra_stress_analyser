import Foundation
import SwiftUI

// MARK: - Summary

/// A coarse, historical snapshot of one family member's data. Nothing
/// live, nothing per-second — see the design note on `FamilyDashboardView`
/// for why "aggregate only" is a deliberate boundary, not just a
/// simplification.
struct FamilyMemberSummary: Identifiable, Sendable {
    var id: UUID { profile.id }
    let profile: UserProfile
    let totalSessions: Int
    let lastActiveAt: Date?
    let currentStreak: Int
    let recentAverageStress: Double?
}

// MARK: - Coordinator

@MainActor
final class FamilyDashboardCoordinator: ObservableObject {

    @Published private(set) var summaries: [FamilyMemberSummary] = []
    @Published private(set) var isLoading = false

    /// Reads each profile's own summary and goals files directly —
    /// never by constructing a full `AppModel` per family member, which
    /// would spin up a `BiometricEngine` (and the camera) for everyone
    /// in the house just to peek at their step count. This is cheap
    /// enough (a handful of small JSON files per profile, at most a
    /// handful of profiles) that it runs straight on the main actor
    /// rather than the `Task.detached` pattern Insights and Coach use
    /// for genuinely large per-session aggregation.
    func refresh(profiles: [UserProfile]) {
        isLoading = true
        defer { isLoading = false }

        summaries = profiles.map { profile in
            let sessionStore = FileSessionStore(
                appSupportSubdirectory: "\(profile.storageRoot)/Sessions"
            )
            let goalsStore = FileGoalsStore(appSupportSubdirectory: profile.storageRoot)

            let sessionSummaries = sessionStore.loadSummaries()  // newest-first
            let goalsState = goalsStore.load()

            let recentStress = sessionSummaries.prefix(5).map(\.averageStress)
            let averageStress = recentStress.isEmpty ? nil : recentStress.average

            return FamilyMemberSummary(
                profile: profile,
                totalSessions: sessionSummaries.count,
                lastActiveAt: sessionSummaries.first?.startedAt,
                currentStreak: goalsState.streak.current,
                recentAverageStress: averageStress
            )
        }
    }
}
