import SwiftUI

struct CoachTabView: View {
    @ObservedObject var coordinator: CoachCoordinator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                header

                if coordinator.recommendations.isEmpty {
                    emptyState
                } else {
                    ForEach(coordinator.recommendations) { recommendation in
                        RecommendationCard(recommendation: recommendation)
                    }
                }

                if !coordinator.ranked.isEmpty {
                    rankingSection
                }

                if !coordinator.categoryRanked.isEmpty {
                    categorySection
                }

                if !coordinator.fastestRecovery.isEmpty {
                    fastestSection
                }

                methodNote
            }
            .padding(Spacing.xl)
        }
        .task { await coordinator.refresh() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Coach")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)

            Text("What's actually worked for you, based on your own sessions")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 26))
                .foregroundStyle(.white.opacity(0.3))

            Text("Not enough data yet")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white.opacity(0.75))

            Text("Use a breathing technique or meditation a couple of times and recommendations will start showing up here.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(Color.white.opacity(0.03))
        .cornerRadius(12)
    }

    private var rankingSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Your techniques, ranked")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)

            ForEach(coordinator.ranked) { item in
                HStack(spacing: Spacing.md) {
                    Image(systemName: item.kind.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(BrandColor.teal)
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.kind.name)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                        Text("\(item.attempts) uses · \(item.confidence.label)")
                            .font(.system(size: 10))
                            .foregroundStyle(item.confidence.color)
                    }

                    Spacer()

                    Text(String(format: "%+.0f pts", item.averageDelta * 100))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(item.averageDelta < 0 ? BrandColor.mint : BrandColor.amber)
                        .monospacedDigit()
                }
                .padding(Spacing.md)
                .background(Color.white.opacity(0.04))
                .cornerRadius(10)
            }
        }
    }

    /// Category-level rollup, sitting above the per-technique list —
    /// "meditation as a whole" versus "breathing as a whole," which the
    /// per-technique ranking above can't show since it keeps every
    /// individual technique separate.
    private var categorySection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("By category")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)

            ForEach(coordinator.categoryRanked) { item in
                HStack(spacing: Spacing.md) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.category.label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                        Text("\(item.attempts) uses · \(item.confidence.label)")
                            .font(.system(size: 10))
                            .foregroundStyle(item.confidence.color)
                    }

                    Spacer()

                    Text(String(format: "%+.0f pts", item.averageDelta * 100))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(item.averageDelta < 0 ? BrandColor.mint : BrandColor.amber)
                        .monospacedDigit()
                }
                .padding(Spacing.md)
                .background(Color.white.opacity(0.04))
                .cornerRadius(10)
            }
        }
    }

    /// Same underlying data as `rankingSection`, reordered by how
    /// quickly each technique's sessions tended to run rather than by
    /// how much they helped. Magnitude and speed are genuinely different
    /// questions — "which helps most" and "which helps fastest" can
    /// have different answers — so this is a separate section rather
    /// than folding a time column into the ranking above.
    private var fastestSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Fastest to help")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)

            ForEach(coordinator.fastestRecovery) { item in
                HStack(spacing: Spacing.md) {
                    Image(systemName: item.kind.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(BrandColor.teal)
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.kind.name)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                        Text("\(item.attempts) uses · \(item.confidence.label)")
                            .font(.system(size: 10))
                            .foregroundStyle(item.confidence.color)
                    }

                    Spacer()

                    Text(DurationFormatter.mmss(item.averageDuration))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(BrandColor.mint)
                        .monospacedDigit()
                }
                .padding(Spacing.md)
                .background(Color.white.opacity(0.04))
                .cornerRadius(10)
            }
        }
    }

    /// Permanent, not a one-time disclosure. "Coach" plus a ranked list
    /// with confidence badges reads as an ML feature whether or not it
    /// is one, so the tab says plainly what's actually behind the
    /// numbers every time it's opened, not just the first time.
    private var methodNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("How this works")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))

            Text("This isn't a trained model — it's averages and sample counts from your own recorded sessions, comparing your stress reading just before and just after each technique. More uses make a number more reliable, which is why every recommendation shows how much data backs it.")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)

            Text("It can't see your calendar or what you were doing beforehand — only how your readings moved around each session.")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)

            Text("This only ranks what the app can actually see you do — breathing, meditation, and the game. It doesn't track exercise or anything else outside the app, so it can't include those in the comparison.")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.md)
        .background(Color.white.opacity(0.03))
        .cornerRadius(8)
    }
}

// MARK: - Recommendation Card

struct RecommendationCard: View {
    let recommendation: CoachRecommendation

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Image(systemName: recommendation.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(BrandColor.amber)

                Spacer()

                Text(recommendation.confidence.label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(recommendation.confidence.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(recommendation.confidence.color.opacity(0.15), in: Capsule())
            }

            Text(recommendation.headline)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            Text(recommendation.detail)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.lg)
        .background(Color.white.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(BrandColor.amber.opacity(0.2), lineWidth: 1)
        )
        .cornerRadius(12)
    }
}

// MARK: - Preview

#if DEBUG
@MainActor
private func makeCoachPreviewCoordinator() -> CoachCoordinator {
    let records: [EffectivenessRecord] = [
        EffectivenessRecord(kind: .breathing(id: "builtin.478", name: "4-7-8"), startedAt: Date(), duration: 152, stressBefore: 0.62, stressAfter: 0.41, sampleCount: 40),
        EffectivenessRecord(kind: .breathing(id: "builtin.478", name: "4-7-8"), startedAt: Date(), duration: 148, stressBefore: 0.58, stressAfter: 0.44, sampleCount: 38),
        EffectivenessRecord(kind: .breathing(id: "builtin.box", name: "Box breathing"), startedAt: Date(), duration: 180, stressBefore: 0.55, stressAfter: 0.50, sampleCount: 45),
        EffectivenessRecord(kind: .meditation(id: "med.breath.5", name: "Five minutes with the breath"), startedAt: Date(), duration: 300, stressBefore: 0.48, stressAfter: 0.30, sampleCount: 80)
    ]

    // `ranked`/`recommendations` are `private(set)` — populated by the
    // view's own `.task { await coordinator.refresh() }` on appear, same
    // as it would be at runtime, rather than poked from outside here.
    return CoachCoordinator(
        store: InMemoryCoachStore(records: records),
        sessionStore: InMemorySessionStore()
    )
}

#Preview {
    CoachTabView(coordinator: makeCoachPreviewCoordinator())
        .frame(width: 420, height: 760)
        .background(BrandColor.slate)
}
#endif
