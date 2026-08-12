import SwiftUI

// MARK: - Player

/// Full-bleed meditation player.
///
/// Deliberately sparse, and deliberately **without a live stress
/// readout**. Watching your own stress number while trying to meditate
/// turns the practice into self-surveillance — you end up monitoring the
/// metric instead of doing the thing the metric measures. A heart-rate
/// glyph is shown only as a quiet confirmation that recording is
/// happening; the numbers come afterwards.
struct MeditationPlayerView: View {
    @ObservedObject var coordinator: MeditationCoordinator
    let meditation: Meditation

    @State private var breathScale: CGFloat = 0.6
    @State private var breathTask: Task<Void, Never>?

    private var engine: MeditationSessionEngine { coordinator.engine }

    var body: some View {
        ZStack {
            backdrop

            VStack(spacing: Spacing.xxl) {
                topBar
                Spacer()
                visualisation
                cueText
                Spacer()
                transport
            }
            .padding(Spacing.xxl)
            .frame(maxWidth: 460)
        }
        .onAppear { startBreathAnimationIfNeeded() }
        .onDisappear { breathTask?.cancel() }
    }

    // MARK: Backdrop

    private var backdrop: some View {
        LinearGradient(
            colors: [
                meditation.category.color.opacity(0.22),
                BrandColor.slate
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
        .overlay(Rectangle().fill(.black.opacity(0.55)).ignoresSafeArea())
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(meditation.title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                Text(meditation.category.label)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }

            Spacer()

            // Quiet confirmation that recording is happening, with no
            // number attached — see the note on this view.
            if coordinator.engine.isRunning {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.3))
                    .help("Stress is being recorded — you'll see it after")
            }

            Button {
                coordinator.end()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Visualisation

    private var visualisation: some View {
        ZStack {
            Circle()
                .fill(meditation.category.color.opacity(0.18))
                .frame(width: 260, height: 260)
                .blur(radius: 34)
                .scaleEffect(breathScale)

            Circle()
                .fill(meditation.category.color.opacity(0.30))
                .frame(width: 180, height: 180)
                .blur(radius: 16)
                .scaleEffect(breathScale)

            Circle()
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
                .frame(width: 200, height: 200)

            // Elapsed progress, thin and unobtrusive.
            Circle()
                .trim(from: 0, to: engine.progress)
                .stroke(
                    meditation.category.color.opacity(0.7),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )
                .frame(width: 200, height: 200)
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.3), value: engine.progress)

            Text(DurationFormatter.mmss(engine.remaining))
                .font(.system(size: 30, weight: .light, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
                .monospacedDigit()
        }
        .frame(height: 280)
    }

    // MARK: Cue

    private var cueText: some View {
        VStack(spacing: 8) {
            Text(engine.currentCue?.text ?? "")
                .font(.title3.weight(.regular))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
                .id(engine.currentCue?.id)
                .transition(.opacity)

            if let subtext = engine.currentCue?.subtext {
                Text(subtext)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(minHeight: 70)
        .animation(.easeInOut(duration: 0.6), value: engine.currentCue?.id)
    }

    // MARK: Transport

    private var transport: some View {
        HStack(spacing: Spacing.xl) {
            Button {
                engine.isPaused ? engine.resume() : engine.pause()
            } label: {
                Image(systemName: engine.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.10), in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.85))

            Button {
                coordinator.toggleFavourite(meditation)
            } label: {
                Image(systemName: coordinator.isFavourite(meditation) ? "heart.fill" : "heart")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.10), in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(coordinator.isFavourite(meditation) ? BrandColor.coral : .white.opacity(0.6))
        }
    }

    // MARK: Breath animation

    /// Ambient pacing for breath-focused meditations only.
    ///
    /// Open-awareness practices deliberately don't get this — pacing your
    /// breath is the opposite of letting it be, and a pulsing circle
    /// implicitly instructs you to follow it.
    private func startBreathAnimationIfNeeded() {
        guard meditation.includesBreathPacing,
              let pattern = meditation.breathPattern else {
            breathScale = 0.85
            return
        }

        breathTask?.cancel()
        breathTask = Task {
            while !Task.isCancelled {
                withAnimation(.easeInOut(duration: pattern.inhale)) { breathScale = 1.10 }
                try? await Task.sleep(for: .seconds(pattern.inhale + pattern.holdIn))
                guard !Task.isCancelled else { return }

                withAnimation(.easeInOut(duration: pattern.exhale)) { breathScale = 0.62 }
                try? await Task.sleep(for: .seconds(pattern.exhale + pattern.holdOut))
                guard !Task.isCancelled else { return }
            }
        }
    }
}

// MARK: - Summary

struct MeditationSummaryView: View {
    let summary: MeditationSummary
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: summary.meditation.category.icon)
                .font(.system(size: 36))
                .foregroundStyle(summary.meditation.category.color)

            VStack(spacing: 6) {
                Text(summary.headline)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)

                Text("\(summary.meditation.title) · \(summary.durationText)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }

            comparisonCard

            if summary.totalCompletions > 1 {
                Text("You've completed this one \(summary.totalCompletions) times.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }

            Button("Done", action: onDismiss)
                .buttonStyle(.borderedProminent)
                .tint(summary.meditation.category.color)
        }
        .padding(Spacing.xxl)
        .frame(maxWidth: 400)
        .background(BrandColor.slate)
    }

    /// Before/after readings, with the caveat attached rather than
    /// tucked away. The number and the reason not to over-read it belong
    /// in the same glance — a caveat behind a disclosure triangle is a
    /// caveat nobody sees.
    private var comparisonCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(summary.comparison.headline)
                .font(.callout.weight(.semibold))
                .foregroundStyle(summary.comparison.directionColor)
                .fixedSize(horizontal: false, vertical: true)

            if let detail = summary.comparison.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(summary.comparison.caveat)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.lg)
        .background(Color.white.opacity(0.05))
        .cornerRadius(10)
    }
}

#if DEBUG
#Preview("Summary") {
    MeditationSummaryView(
        summary: MeditationSummary(
            meditation: .fiveMinuteBreath,
            elapsed: 300,
            completedFully: true,
            comparison: MeditationStressComparison(
                before: 0.58,
                after: 0.41,
                sampleCount: 120,
                direction: .lower,
                deltaPoints: -0.17
            ),
            totalCompletions: 3
        ),
        onDismiss: {}
    )
}
#endif
