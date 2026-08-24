import SwiftUI

/// Sidebar tab for configuring and starting focus mode.
struct FocusTabView: View {
    @ObservedObject var coordinator: FocusCoordinator
    @State private var showingCustomConfig = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                header
                presetSection

                if showingCustomConfig {
                    customConfigSection
                }

                startButton
                explanation
            }
            .padding(Spacing.xl)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Focus")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)

            Text(
                coordinator.focusBlocksToday == 0
                    ? "Timed work blocks with quiet monitoring"
                    : "\(coordinator.focusBlocksToday) block\(coordinator.focusBlocksToday == 1 ? "" : "s") completed today"
            )
            .font(.caption)
            .foregroundStyle(.white.opacity(0.6))
        }
    }

    // MARK: - Presets

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Length")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)

            HStack(spacing: Spacing.sm) {
                ForEach(FocusConfiguration.presets, id: \.name) { preset in
                    presetButton(name: preset.name, config: preset.config)
                }
            }

            Button {
                showingCustomConfig.toggle()
            } label: {
                Label(
                    showingCustomConfig ? "Hide custom" : "Customise",
                    systemImage: showingCustomConfig ? "chevron.up" : "slider.horizontal.3"
                )
                .font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(BrandColor.teal)
        }
    }

    private func presetButton(name: String, config: FocusConfiguration) -> some View {
        let isSelected = coordinator.configuration == config

        return Button {
            coordinator.configuration = config
        } label: {
            VStack(spacing: 3) {
                Text(name)
                    .font(.system(size: 11, weight: .semibold))
                Text("\(config.focusMinutes)m")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundStyle(isSelected ? .white : .white.opacity(0.6))
            .background(isSelected ? BrandColor.primaryBlue.opacity(0.25) : Color.white.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? BrandColor.primaryBlue.opacity(0.6) : .clear, lineWidth: 1)
            )
            .cornerRadius(10)
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Custom

    private var customConfigSection: some View {
        VStack(spacing: Spacing.md) {
            stepperRow(
                "Focus",
                value: Binding(
                    get: { coordinator.configuration.focusMinutes },
                    set: { coordinator.configuration.focusMinutes = $0 }
                ),
                range: FocusConfiguration.focusRange
            )

            stepperRow(
                "Break",
                value: Binding(
                    get: { coordinator.configuration.shortBreakMinutes },
                    set: { coordinator.configuration.shortBreakMinutes = $0 }
                ),
                range: FocusConfiguration.breakRange
            )

            stepperRow(
                "Long break",
                value: Binding(
                    get: { coordinator.configuration.longBreakMinutes },
                    set: { coordinator.configuration.longBreakMinutes = $0 }
                ),
                range: FocusConfiguration.breakRange
            )

            stepperRow(
                "Rounds",
                value: Binding(
                    get: { coordinator.configuration.roundsBeforeLongBreak },
                    set: { coordinator.configuration.roundsBeforeLongBreak = $0 }
                ),
                range: FocusConfiguration.roundsRange,
                suffix: ""
            )
        }
        .padding(Spacing.lg)
        .background(Color.white.opacity(0.04))
        .cornerRadius(10)
    }

    private func stepperRow(
        _ label: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        suffix: String = "m"
    ) -> some View {
        HStack {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.8))

            Spacer()

            Stepper("\(value.wrappedValue)\(suffix)", value: value, in: range)
                .foregroundStyle(.white)
                .fixedSize()
        }
    }

    // MARK: - Start

    private var startButton: some View {
        Button {
            coordinator.start()
        } label: {
            Label("Start focus block", systemImage: "play.fill")
                .font(.callout.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(12)
                .background(BrandColor.primaryBlue)
                .foregroundStyle(.white)
                .cornerRadius(10)
                .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(coordinator.isActive)
    }

    // MARK: - Explanation

    /// Says plainly what focus mode does to notifications. A feature that
    /// silently withholds alerts should tell you it's doing that —
    /// otherwise a user who relies on the stress alerts has no way to
    /// know why they stopped arriving.
    private var explanation: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("What happens during focus")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.65))

            bullet("The workspace dims to a timer and nothing else.")
            bullet("Predictive stress alerts are held back until your break.")
            bullet("Stress is still recorded — you'll see it in the summary.")
            bullet("If stress stays high for several minutes, you'll be offered an early break. You can decline it.")
        }
        .padding(Spacing.md)
        .background(Color.white.opacity(0.03))
        .cornerRadius(8)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("·")
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 10))
        .foregroundStyle(.white.opacity(0.5))
    }
}

#if DEBUG
@MainActor
private func makeFocusPreviewCoordinator() -> FocusCoordinator {
    FocusCoordinator()
}

#Preview {
    FocusTabView(coordinator: makeFocusPreviewCoordinator())
        .frame(width: 400, height: 640)
        .background(BrandColor.slate)
}
#endif
