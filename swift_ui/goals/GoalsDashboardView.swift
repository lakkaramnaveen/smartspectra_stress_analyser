import SwiftUI

// MARK: - Dashboard

struct GoalsDashboardView: View {
    @ObservedObject var coordinator: GoalsCoordinator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                streakCard

                if !coordinator.progress.isEmpty {
                    goalsSection
                }

                achievementsSection
                recordsSection
            }
            .padding(Spacing.xl)
        }
        .onAppear { coordinator.refresh() }
        .overlay(alignment: .top) {
            if let celebration = coordinator.pendingCelebrations.first {
                AchievementToast(achievement: celebration) {
                    coordinator.dismissCelebration(celebration)
                }
                .padding(Spacing.lg)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4), value: coordinator.pendingCelebrations.count)
    }

    // MARK: - Streak

    private var streakCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.md) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(
                        coordinator.state.streak.current > 0
                            ? BrandColor.amber
                            : .white.opacity(0.25)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(coordinator.state.streak.current) day streak")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)

                    Text(coordinator.state.streak.encouragement)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("Best")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                    Text("\(coordinator.state.streak.best)")
                        .font(.callout.weight(.bold))
                        .foregroundStyle(BrandColor.amber)
                }
            }

            // Surfacing the grace day explicitly, rather than letting it
            // work invisibly. Knowing a missed day won't cost you the
            // streak is most of the point — it only reduces pressure if
            // the user is aware of it.
            if coordinator.state.streak.graceDaysRemaining > 0 && coordinator.state.streak.current > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 10, weight: .semibold))
                    Text("A missed day won't break this streak.")
                        .font(.system(size: 11))
                }
                .foregroundStyle(BrandColor.mint.opacity(0.9))
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }

    // MARK: - Goals

    private var goalsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("This week")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)

            ForEach(coordinator.progress) { item in
                GoalRow(progress: item)
            }
        }
    }

    // MARK: - Achievements

    private var achievementsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Text("Achievements")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text("\(coordinator.unlockedAchievements.count) of \(AchievementCatalog.all.count)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 86), spacing: Spacing.md)],
                spacing: Spacing.md
            ) {
                ForEach(coordinator.unlockedAchievements) { achievement in
                    AchievementBadge(achievement: achievement, isUnlocked: true)
                }
                ForEach(coordinator.lockedAchievements) { achievement in
                    AchievementBadge(achievement: achievement, isUnlocked: false)
                }
            }
        }
    }

    // MARK: - Records

    private var recordsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Personal records")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)

            VStack(spacing: Spacing.sm) {
                if let calm = coordinator.state.records.longestCalmRunSeconds, calm > 0 {
                    StatsRow(
                        icon: "leaf.fill",
                        label: "Longest calm stretch",
                        value: DurationFormatter.mmss(calm),
                        color: BrandColor.mint
                    )
                }

                if let recovery = coordinator.state.records.fastestRecoverySeconds {
                    StatsRow(
                        icon: "arrow.uturn.down.circle",
                        label: "Fastest recovery",
                        value: "\(Int(recovery))s",
                        color: BrandColor.teal
                    )
                }

                StatsRow(
                    icon: "record.circle",
                    label: "Sessions recorded",
                    value: "\(coordinator.state.records.totalSessions)",
                    color: BrandColor.primaryBlue
                )

                StatsRow(
                    icon: "wind",
                    label: "Breathing breaks",
                    value: "\(coordinator.state.records.totalBreathingCompleted)",
                    color: BrandColor.lightBlue
                )
            }

            // Records are presented as history, not as a bar to clear.
            // A user who treats "lowest peak stress ever" as a target
            // every session has turned a keepsake into a pressure
            // source, which is the opposite of the intent.
            Text("These are moments from your history — worth remembering, not targets to beat.")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.45))
        }
    }
}

// MARK: - Goal Row

struct GoalRow: View {
    let progress: GoalProgress

    private var accent: Color {
        progress.isComplete ? BrandColor.mint : BrandColor.teal
    }

    var body: some View {
        HStack(spacing: Spacing.lg) {
            LabeledProgressRing(
                fraction: progress.fraction,
                color: accent,
                icon: progress.goal.kind.icon,
                size: 62
            )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(progress.goal.title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white)

                    if progress.isComplete {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(BrandColor.mint)
                    }
                }

                Text(progress.goal.subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)

                Text(progress.statusText)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(accent)
            }

            Spacer(minLength: 0)
        }
        .padding(Spacing.md)
        .background(Color.white.opacity(0.04))
        .cornerRadius(12)
    }
}

// MARK: - Achievement Badge

struct AchievementBadge: View {
    let achievement: Achievement
    let isUnlocked: Bool

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(
                        isUnlocked
                            ? achievement.tier.color.opacity(0.18)
                            : Color.white.opacity(0.04)
                    )
                    .frame(width: 48, height: 48)

                Image(systemName: isUnlocked ? achievement.icon : "lock.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(
                        isUnlocked ? achievement.tier.color : .white.opacity(0.25)
                    )
            }

            Text(achievement.title)
                .font(.system(size: 9, weight: .semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(isUnlocked ? .white.opacity(0.85) : .white.opacity(0.4))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        // Locked achievements still show their requirement. Hiding it
        // makes the grid a mystery box; showing it makes it a roadmap.
        .help(achievement.detail)
    }
}

// MARK: - Celebration Toast

struct AchievementToast: View {
    let achievement: Achievement
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: achievement.icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(achievement.tier.color)

            VStack(alignment: .leading, spacing: 2) {
                Text(achievement.title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                Text(achievement.detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }

            Spacer(minLength: 0)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(Spacing.lg)
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(achievement.tier.color.opacity(0.45), lineWidth: 1)
        )
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
    }
}

// MARK: - Preview

#if DEBUG
@MainActor
private func makeGoalsPreviewCoordinator() -> GoalsCoordinator {
    let sessionStore = InMemorySessionStore()
    let calendar = Calendar.current

    for dayOffset in 0..<9 {
        guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) else { continue }
        var recording = SessionRecording(
            startedAt: day,
            difficulty: "medium",
            snapshots: (0..<200).map { i in
                SessionSnapshot(
                    timestamp: day.addingTimeInterval(Double(i)),
                    stressScore: i < 120 ? 0.22 : 0.55,
                    heartRate: 72,
                    breathingRate: 14,
                    eda: 0.02,
                    emotionalState: "Calm",
                    gazeConfidence: 0.9
                )
            }
        )
        recording.endedAt = day.addingTimeInterval(200)
        try? sessionStore.save(recording)
    }

    var state = GoalsState.initial
    state.records.totalBreathingCompleted = 12

    let coordinator = GoalsCoordinator(
        store: InMemoryGoalsStore(state: state),
        sessionStore: sessionStore
    )
    coordinator.refresh()
    return coordinator
}

#Preview {
    GoalsDashboardView(coordinator: makeGoalsPreviewCoordinator())
        .frame(width: 420, height: 720)
        .background(BrandColor.slate)
}
#endif
