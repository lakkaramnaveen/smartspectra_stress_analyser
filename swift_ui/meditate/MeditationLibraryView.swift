import SwiftUI

struct MeditationLibraryView: View {
    @ObservedObject var coordinator: MeditationCoordinator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                header

                if !coordinator.favourites.isEmpty {
                    section("Favourites", coordinator.favourites)
                }

                section("All", coordinator.catalog)

                audioNote
            }
            .padding(Spacing.xl)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Meditation")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)

            Text(
                coordinator.preferences.totalCompleted == 0
                    ? "Short guided sittings"
                    : "\(coordinator.preferences.totalCompleted) sittings completed"
            )
            .font(.caption)
            .foregroundStyle(.white.opacity(0.6))
        }
    }

    private func section(_ title: String, _ meditations: [Meditation]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)

            ForEach(meditations) { meditation in
                MeditationRow(
                    meditation: meditation,
                    isFavourite: coordinator.isFavourite(meditation),
                    completions: coordinator.completionCount(for: meditation),
                    onStart: { coordinator.begin(meditation) },
                    onToggleFavourite: { coordinator.toggleFavourite(meditation) }
                )
            }
        }
    }

    /// Says plainly that these are text-guided. Someone expecting a
    /// narrated meditation and getting silence would reasonably think
    /// the app was broken.
    private var audioNote: some View {
        Text("These sittings are guided by on-screen cues rather than narration — you can run them anywhere without headphones.")
            .font(.system(size: 10))
            .foregroundStyle(.white.opacity(0.4))
            .fixedSize(horizontal: false, vertical: true)
            .padding(Spacing.md)
            .background(Color.white.opacity(0.03))
            .cornerRadius(8)
    }
}

// MARK: - Row

struct MeditationRow: View {
    let meditation: Meditation
    let isFavourite: Bool
    let completions: Int
    let onStart: () -> Void
    let onToggleFavourite: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: meditation.category.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(meditation.category.color)
                    .frame(width: 20, height: 20)

                Text(meditation.title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)

                Spacer()

                Text("\(meditation.minutes)m")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(meditation.category.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(meditation.category.color.opacity(0.15), in: Capsule())
            }

            Text(meditation.summary)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Spacing.md) {
                if meditation.includesBreathPacing {
                    Label("Breath-paced", systemImage: "wind")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.45))
                }

                if completions > 0 {
                    Label("\(completions)", systemImage: "checkmark")
                        .font(.system(size: 10))
                        .foregroundStyle(BrandColor.mint.opacity(0.8))
                }

                Spacer()

                Button(action: onToggleFavourite) {
                    Image(systemName: isFavourite ? "heart.fill" : "heart")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(isFavourite ? BrandColor.coral : .white.opacity(0.35))

                Button("Begin", action: onStart)
                    .buttonStyle(.borderedProminent)
                    .tint(meditation.category.color)
                    .controlSize(.small)
            }
        }
        .padding(Spacing.lg)
        .background(Color.white.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
        .cornerRadius(12)
    }
}

#if DEBUG
@MainActor
private func makeMeditationPreviewCoordinator() -> MeditationCoordinator {
    MeditationCoordinator(store: InMemoryMeditationPreferencesStore())
}

#Preview {
    MeditationLibraryView(coordinator: makeMeditationPreviewCoordinator())
        .frame(width: 420, height: 720)
        .background(BrandColor.slate)
}
#endif
