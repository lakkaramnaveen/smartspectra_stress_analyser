import SwiftUI

/// Recovery panel.
///
/// A dismissible card, deliberately **not** a modal. Recovery begins
/// moments after a breathing intervention ends, so a full-screen
/// takeover here would mean two overlays back to back at exactly the
/// point the user is trying to return to work. It also isn't urgent —
/// nothing needs doing, which is rather the message — and a blocking
/// overlay would contradict that.
struct RecoveryPanel: View {
    let state: RecoveryState
    let hasSettled: Bool
    let onDismiss: () -> Void
    let onStartBreathing: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            header
            progressTrack
            message

            if !hasSettled, let suggestion = state.suggestion {
                suggestionRow(suggestion)
            }

            readings
        }
        .padding(Spacing.lg)
        .frame(maxWidth: 340, alignment: .leading)
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(state.phase.color.opacity(0.35), lineWidth: 1)
        )
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: state.phase.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(state.phase.color)

            Text(state.phase.label)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white)

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Progress

    /// Peak → baseline descent as a filled track.
    ///
    /// Framed as distance travelled, not as a score being beaten. The
    /// endpoint is labelled "your usual" rather than "goal" — there's no
    /// target here, just a return to where the person normally sits.
    private var progressTrack: some View {
        VStack(spacing: 5) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.12))

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [BrandColor.amber, state.phase.color],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: proxy.size.width * CGFloat(state.progress))
                }
            }
            .frame(height: 6)
            .animation(.easeOut(duration: 0.8), value: state.progress)

            HStack {
                Text("Peak")
                Spacer()
                Text("Your usual")
            }
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.white.opacity(0.45))
        }
    }

    // MARK: Message

    private var message: some View {
        Text(state.message)
            .font(.caption)
            .foregroundStyle(.white.opacity(0.8))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func suggestionRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "wind")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(BrandColor.mint)

            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            Button("Breathe", action: onStartBreathing)
                .buttonStyle(.borderless)
                .controlSize(.small)
                .font(.system(size: 11, weight: .semibold))
                .tint(BrandColor.mint)
        }
    }

    // MARK: Readings

    private var readings: some View {
        HStack(spacing: Spacing.lg) {
            reading("Peak", state.peakScore, BrandColor.coral)
            reading("Now", state.currentScore, state.phase.color)
            reading("Usual", state.baseline, BrandColor.mediumGray)

            Spacer(minLength: 0)

            Text(DurationFormatter.mmss(state.elapsedSincePeak))
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.4))
                .monospacedDigit()
        }
    }

    private func reading(_ label: String, _ value: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
            Text(String(format: "%.0f%%", value * 100))
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
        }
    }
}

#if DEBUG
#Preview("Easing") {
    RecoveryPanel(
        state: RecoveryState(
            phase: .easing,
            peakScore: 0.96,
            currentScore: 0.72,
            baseline: 0.31,
            progress: 0.37,
            peakAt: Date().addingTimeInterval(-95)
        ),
        hasSettled: false,
        onDismiss: {},
        onStartBreathing: {}
    )
    .padding(32)
    .background(BrandColor.slate)
}

#Preview("Settled") {
    RecoveryPanel(
        state: RecoveryState(
            phase: .settled,
            peakScore: 0.96,
            currentScore: 0.34,
            baseline: 0.31,
            progress: 1.0,
            peakAt: Date().addingTimeInterval(-260)
        ),
        hasSettled: true,
        onDismiss: {},
        onStartBreathing: {}
    )
    .padding(32)
    .background(BrandColor.slate)
}
#endif
