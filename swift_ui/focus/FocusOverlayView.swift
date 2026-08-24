import SwiftUI

// MARK: - Focus Overlay

/// Dimmed timer overlay shown while focus mode runs.
///
/// Intentionally sparse. The point of focus mode is fewer things
/// competing for attention, so this shows a ring, a countdown, and three
/// controls — no vitals, no charts, no live stress readout. Stress is
/// still being recorded; it's simply reported afterwards rather than
/// dangled in front of someone trying to concentrate. A visible stress
/// number during focus invites monitoring your own stress instead of
/// working, which is its own kind of distraction.
struct FocusOverlayView: View {
    @ObservedObject var coordinator: FocusCoordinator

    private var phase: FocusPhase { coordinator.engine.phase }

    var body: some View {
        ZStack {
            // Dim rather than fully obscure — the workspace stays faintly
            // visible so the app doesn't feel like it's been taken over.
            Rectangle()
                .fill(.black.opacity(0.82))
                .ignoresSafeArea()

            VStack(spacing: Spacing.xl) {
                phaseLabel
                timerRing
                controls

                if coordinator.earlyExitOffered {
                    earlyExitCard
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(Spacing.xxl)
            .frame(maxWidth: 420)
        }
        .animation(.easeInOut, value: coordinator.earlyExitOffered)
    }

    // MARK: Phase label

    private var phaseLabel: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: phase.icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(phase.label)
                    .font(.callout.weight(.semibold))
            }
            .foregroundStyle(phase.color)

            if coordinator.engine.completedFocusRounds > 0 {
                Text("Round \(coordinator.engine.completedFocusRounds + (phase == .focus ? 1 : 0))")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    // MARK: Timer

    private var timerRing: some View {
        ZStack {
            ProgressRing(
                fraction: coordinator.engine.progress,
                color: phase.color,
                lineWidth: 12
            )
            .frame(width: 220, height: 220)

            VStack(spacing: 4) {
                Text(DurationFormatter.mmss(coordinator.engine.remaining))
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .contentTransition(.numericText())

                if coordinator.engine.isPaused {
                    Text("Paused")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BrandColor.amber)
                }
            }
        }
    }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: Spacing.lg) {
            controlButton(
                icon: coordinator.engine.isPaused ? "play.fill" : "pause.fill",
                label: coordinator.engine.isPaused ? "Resume" : "Pause"
            ) {
                coordinator.engine.isPaused ? coordinator.resume() : coordinator.pause()
            }

            controlButton(icon: "forward.end.fill", label: "Skip") {
                coordinator.skip()
            }

            controlButton(icon: "stop.fill", label: "End") {
                coordinator.stop()
            }
        }
    }

    private func controlButton(
        icon: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 22, height: 22)
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
            }
            .frame(width: 64)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.08))
            .cornerRadius(10)
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.85))
    }

    // MARK: Early exit offer

    /// Shown only after several unbroken minutes of high stress.
    ///
    /// Phrased as an option, not a verdict. It doesn't pause the timer or
    /// force anything — someone who's fine can ignore it and keep
    /// working, which is why the copy avoids implying they're doing
    /// something wrong.
    private var earlyExitCard: some View {
        VStack(spacing: Spacing.md) {
            Text("Your stress has stayed high for a few minutes.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.8))

            HStack(spacing: Spacing.md) {
                Button("Keep going") {
                    coordinator.declineEarlyExit()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Take the break now") {
                    coordinator.skip()
                }
                .buttonStyle(.borderedProminent)
                .tint(BrandColor.mint)
                .controlSize(.small)
            }
        }
        .padding(Spacing.lg)
        .background(Color.white.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(BrandColor.amber.opacity(0.35), lineWidth: 1)
        )
        .cornerRadius(12)
    }
}

// MARK: - Summary Sheet

struct FocusSummaryView: View {
    let summary: FocusSummary
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: summary.completedFully ? "checkmark.circle.fill" : "circle.dashed")
                .font(.system(size: 40))
                .foregroundStyle(summary.completedFully ? summary.phase.color : .white.opacity(0.4))

            VStack(spacing: 6) {
                Text(summary.headline)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)

                Text(summary.detail)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if summary.hadStressData {
                HStack(spacing: Spacing.md) {
                    if let average = summary.averageStress {
                        StatsCard(
                            icon: "waveform.path.ecg",
                            label: "Average",
                            value: String(format: "%.0f%%", average * 100),
                            color: StressLevel.classify(average).color
                        )
                    }
                    if let peak = summary.peakStress {
                        StatsCard(
                            icon: "arrow.up",
                            label: "Peak",
                            value: String(format: "%.0f%%", peak * 100),
                            color: StressLevel.classify(peak).color
                        )
                    }
                }
            }

            // The deferred break suggestion. Surfaced here — at the
            // boundary, where the timer was ending anyway — rather than
            // mid-block, which is the whole point of focus mode.
            if summary.suggestsLongerBreak {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lightbulb")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(BrandColor.amber)
                    Text("That block ran hot. A longer break, or a breathing exercise, might be worth it before the next one.")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Spacing.md)
                .background(Color.white.opacity(0.05))
                .cornerRadius(8)
            }

            Button("Continue", action: onDismiss)
                .buttonStyle(.borderedProminent)
                .tint(summary.phase.color)
        }
        .padding(Spacing.xxl)
        .frame(maxWidth: 380)
        .background(BrandColor.slate)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Summary") {
    FocusSummaryView(
        summary: FocusSummary(
            phase: .focus,
            plannedDuration: 1500,
            actualDuration: 1500,
            completedFully: true,
            roundNumber: 2,
            averageStress: 0.52,
            peakStress: 0.81,
            sustainedHighStressSeconds: 320
        ),
        onDismiss: {}
    )
}
#endif
