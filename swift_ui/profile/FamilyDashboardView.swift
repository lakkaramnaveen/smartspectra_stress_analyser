import SwiftUI

struct FamilyDashboardView: View {
    let profiles: [UserProfile]
    @StateObject private var coordinator = FamilyDashboardCoordinator()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    ForEach(coordinator.summaries) { summary in
                        MemberSummaryCard(summary: summary)
                    }
                    boundaryNote
                }
                .padding(Spacing.xl)
            }
        }
        .background(BrandColor.slate)
        .onAppear { coordinator.refresh(profiles: profiles) }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Family overview")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                Text("A high-level look, not a live feed")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .buttonStyle(.plain)
        }
        .padding(Spacing.xl)
    }

    /// Explains the actual privacy boundary — or rather, the lack of a
    /// technical one. Worth stating plainly rather than letting "Family
    /// overview" imply a permissions model that doesn't exist: every
    /// profile's files sit in the same macOS user account's Application
    /// Support folder, so this dashboard, or a curious person poking
    /// around in Finder, can see any profile's summary data. That's a
    /// genuinely different guarantee than a teenager's stress readings
    /// being invisible to a parent by design, and pretending otherwise
    /// would be the wrong kind of reassuring.
    private var boundaryNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("About privacy between profiles")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))

            Text("These profiles share one Mac user account, so there's no real access boundary between them — anyone using this account can see any profile's files, including from this dashboard. It's a way to organise separate people's data, not a security wall between family members. If that separation matters, it needs separate macOS user accounts, which this app can't create for you.")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.md)
        .background(Color.white.opacity(0.03))
        .cornerRadius(8)
    }
}

// MARK: - Member Card

private struct MemberSummaryCard: View {
    let summary: FamilyMemberSummary

    var body: some View {
        HStack(spacing: Spacing.lg) {
            ZStack {
                Circle()
                    .fill(summary.profile.colorTag.color.opacity(0.25))
                    .frame(width: 48, height: 48)
                Text(summary.profile.initial)
                    .font(.callout.weight(.bold))
                    .foregroundStyle(summary.profile.colorTag.color)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(summary.profile.name)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)

                Text(lastActiveText)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(BrandColor.amber)
                    Text("\(summary.currentStreak)d")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }

                if let stress = summary.recentAverageStress {
                    Text("Recent avg \(String(format: "%.0f%%", stress * 100))")
                        .font(.system(size: 10))
                        .foregroundStyle(StressLevel.classify(stress).color)
                }
            }
        }
        .padding(Spacing.lg)
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }

    private var lastActiveText: String {
        guard let last = summary.lastActiveAt else {
            return "No sessions yet"
        }
        return "\(summary.totalSessions) sessions · last \(last.formatted(date: .abbreviated, time: .omitted))"
    }
}

#if DEBUG
#Preview {
    FamilyDashboardView(profiles: [
        .default,
        UserProfile(name: "Sam", relationship: .teen, colorTag: .coral)
    ])
    .frame(width: 480, height: 560)
}
#endif
