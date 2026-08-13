import SwiftUI

// MARK: - Tab

struct ErgonomicsTabView: View {
    @ObservedObject var coordinator: ErgonomicsCoordinator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                header
                signalCard
                statsGrid
                settings
                methodologyNote
            }
            .padding(Spacing.xl)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Desk habits")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)

            Text("Screen time and neck-strain reminders")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    // MARK: Signal

    /// Tracking quality is surfaced prominently rather than buried,
    /// because every downward-gaze figure below is only as good as this.
    /// A user seeing "18 minutes looking down" deserves to know whether
    /// the camera could actually see them for those 18 minutes.
    private var signalCard: some View {
        HStack(spacing: Spacing.md) {
            Circle()
                .fill(coordinator.stats.quality.color)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(coordinator.stats.quality.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))

                if !coordinator.hasBaseline {
                    Text("Calibrating to your usual position…")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }

            Spacer()

            Button("Recalibrate") { coordinator.recalibrate() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Re-anchor to where you're sitting now — use this after changing your setup")
        }
        .padding(Spacing.md)
        .background(Color.white.opacity(0.04))
        .cornerRadius(10)
    }

    // MARK: Stats

    private var statsGrid: some View {
        VStack(spacing: Spacing.sm) {
            StatsRow(
                icon: "display",
                label: "Screen time",
                value: DurationFormatter.mmss(coordinator.stats.screenTimeSeconds),
                color: BrandColor.primaryBlue
            )

            StatsRow(
                icon: "clock",
                label: "Since last break",
                value: DurationFormatter.mmss(coordinator.stats.timeSinceBreakSeconds),
                color: BrandColor.teal
            )

            if coordinator.hasBaseline {
                StatsRow(
                    icon: "arrow.down",
                    label: "Looking down",
                    value: DurationFormatter.mmss(coordinator.stats.downwardGazeSeconds),
                    color: BrandColor.amber
                )

                StatsRow(
                    icon: "arrow.down.to.line",
                    label: "Longest stretch",
                    value: DurationFormatter.mmss(coordinator.stats.longestDownwardStretchSeconds),
                    color: BrandColor.lightBlue
                )
            }

            StatsRow(
                icon: "figure.walk",
                label: "Breaks taken",
                value: "\(coordinator.stats.breaksTaken)",
                color: BrandColor.mint
            )
        }
    }

    // MARK: Settings

    private var settings: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Reminders")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)

            Toggle("Enabled", isOn: $coordinator.config.isEnabled)
                .toggleStyle(.switch)
                .tint(BrandColor.primaryBlue)

            if coordinator.config.isEnabled {
                stepper(
                    "Break reminder",
                    value: $coordinator.config.screenBreakMinutes,
                    range: ErgonomicsConfig.screenBreakRange
                )

                stepper(
                    "Neck reminder",
                    value: $coordinator.config.neckFlexionMinutes,
                    range: ErgonomicsConfig.neckFlexionRange
                )

                Toggle("Eye rest reminders", isOn: $coordinator.config.eyeRestEnabled)
                    .toggleStyle(.switch)
                    .tint(BrandColor.primaryBlue)

                if coordinator.config.eyeRestEnabled {
                    stepper(
                        "Eye rest every",
                        value: $coordinator.config.eyeRestMinutes,
                        range: ErgonomicsConfig.eyeRestRange
                    )
                }
            }
        }
        .padding(Spacing.lg)
        .background(Color.white.opacity(0.04))
        .cornerRadius(10)
    }

    private func stepper(
        _ label: String,
        value: Binding<Int>,
        range: ClosedRange<Int>
    ) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))
            Spacer()
            Stepper("\(value.wrappedValue) min", value: value, in: range, step: 5)
                .fixedSize()
                .foregroundStyle(.white)
        }
    }

    // MARK: Methodology

    /// States what the feature does and doesn't measure.
    ///
    /// Worth the space: "ergonomics" and gaze tracking together invite
    /// the assumption that the app is assessing posture, which it can't
    /// do. Someone trusting a wrong posture assessment could reinforce a
    /// genuinely bad setup, so the limitation is stated rather than left
    /// to be inferred.
    private var methodologyNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("What this measures")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.65))

            Text("These are timers, plus how far your gaze sits below where it started this session. That's a reasonable proxy for looking down at a keyboard or phone, and for gradually leaning toward the desk.")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)

            Text("It can't see your back or shoulders, so it can't tell you whether your posture is good — camera height alone changes these readings completely. For an actual setup assessment, someone looking at you beats a webcam.")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.md)
        .background(Color.white.opacity(0.03))
        .cornerRadius(8)
    }
}

// MARK: - Nudge Banner

struct ErgonomicsNudgeBanner: View {
    let nudge: ErgonomicsNudge
    let onDismiss: () -> Void
    let onBreakTaken: () -> Void

    private var showsBreakAction: Bool {
        if case .screenBreak = nudge.kind { return true }
        if case .eyeRest = nudge.kind { return true }
        return false
    }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: nudge.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(BrandColor.lightBlue)

            VStack(alignment: .leading, spacing: 4) {
                Text(nudge.title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)

                Text(nudge.body)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)

                if showsBreakAction {
                    Button("I took a break", action: onBreakTaken)
                        .buttonStyle(.borderless)
                        .tint(BrandColor.mint)
                        .font(.caption.weight(.semibold))
                        .padding(.top, 2)
                }
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
                .stroke(BrandColor.lightBlue.opacity(0.35), lineWidth: 1)
        )
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
    }
}

#if DEBUG
@MainActor
private func makeErgonomicsPreviewCoordinator() -> ErgonomicsCoordinator {
    ErgonomicsCoordinator(store: InMemoryErgonomicsConfigStore())
}

#Preview("Tab") {
    ErgonomicsTabView(coordinator: makeErgonomicsPreviewCoordinator())
        .frame(width: 400, height: 700)
        .background(BrandColor.slate)
}

#Preview("Nudge") {
    ErgonomicsNudgeBanner(
        nudge: ErgonomicsNudge(
            kind: .screenBreak(minutes: 52),
            title: "You've been at this 52 minutes",
            body: "A few minutes away from the screen would be a good idea if you can spare them.",
            raisedAt: Date()
        ),
        onDismiss: {},
        onBreakTaken: {}
    )
    .padding()
    .frame(width: 420)
    .background(BrandColor.slate)
}
#endif
