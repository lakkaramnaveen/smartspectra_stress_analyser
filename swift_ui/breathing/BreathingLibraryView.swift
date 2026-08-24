import SwiftUI

// MARK: - Library

struct BreathingLibraryView: View {
    @ObservedObject var coordinator: BreathingCoordinator
    @State private var editingTechnique: BreathingTechnique?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                header

                ForEach(coordinator.allTechniques) { technique in
                    TechniqueCard(
                        technique: technique,
                        isSelected: technique.id == coordinator.preferences.selectedTechniqueID,
                        completions: coordinator.completionCount(for: technique),
                        onSelect: { coordinator.select(technique) },
                        onTry: { coordinator.begin(technique) },
                        onEdit: technique.isBuiltIn ? nil : { editingTechnique = technique },
                        onDelete: technique.isBuiltIn ? nil : { coordinator.deleteCustom(technique) }
                    )
                }

                Button {
                    editingTechnique = .newCustom()
                } label: {
                    Label("Create your own", systemImage: "plus.circle")
                        .font(.callout.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .foregroundStyle(BrandColor.teal)
            }
            .padding(Spacing.xl)
        }
        .sheet(item: $editingTechnique) { technique in
            CustomTechniqueEditor(
                technique: technique,
                onSave: {
                    coordinator.saveCustom($0)
                    editingTechnique = nil
                },
                onCancel: { editingTechnique = nil }
            )
            .frame(minWidth: 420, minHeight: 480)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Breathing")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)

            Text("\(coordinator.preferences.totalCompletions) exercises completed")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
    }
}

// MARK: - Technique Card

struct TechniqueCard: View {
    let technique: BreathingTechnique
    let isSelected: Bool
    let completions: Int
    let onSelect: () -> Void
    let onTry: () -> Void
    let onEdit: (() -> Void)?
    let onDelete: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                Text(technique.name)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)

                Text(technique.pattern.notation)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(BrandColor.teal)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(BrandColor.teal.opacity(0.15), in: Capsule())

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(BrandColor.mint)
                }
            }

            if !technique.summary.isEmpty {
                Text(technique.summary)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
            }

            PhaseTimeline(pattern: technique.pattern)

            HStack(spacing: Spacing.md) {
                Label(
                    "\(technique.cycleCount) cycles · \(DurationFormatter.mmss(technique.totalDuration))",
                    systemImage: "clock"
                )
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.5))

                if completions > 0 {
                    Label("\(completions) done", systemImage: "checkmark")
                        .font(.system(size: 10))
                        .foregroundStyle(BrandColor.mint.opacity(0.8))
                }

                Spacer()
            }

            HStack(spacing: Spacing.sm) {
                Button("Try it", action: onTry)
                    .buttonStyle(.borderedProminent)
                    .tint(BrandColor.teal)
                    .controlSize(.small)

                if !isSelected {
                    Button("Set as default", action: onSelect)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }

                Spacer()

                if let onEdit {
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }

                if let onDelete {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .tint(BrandColor.coral)
                }
            }
        }
        .padding(Spacing.lg)
        .background(Color.white.opacity(isSelected ? 0.07 : 0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isSelected ? BrandColor.mint.opacity(0.4) : Color.white.opacity(0.08),
                    lineWidth: 1
                )
        )
        .cornerRadius(12)
    }
}

// MARK: - Phase Timeline

/// Proportional bar showing how a cycle is divided between phases —
/// makes the difference between 4-7-8 and box breathing legible at a
/// glance, which a numeric notation alone doesn't.
struct PhaseTimeline: View {
    let pattern: BreathingPattern

    private func color(for phase: BreathPhase) -> Color {
        switch phase {
        case .inhale: return BrandColor.mint
        case .holdIn: return BrandColor.teal
        case .exhale: return BrandColor.lightBlue
        case .holdOut: return BrandColor.mediumGray
        }
    }

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 2) {
                ForEach(Array(pattern.activePhases.enumerated()), id: \.offset) { _, entry in
                    let fraction = entry.duration / max(pattern.cycleDuration, 0.001)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(color(for: entry.phase))
                        .frame(width: max(proxy.size.width * CGFloat(fraction) - 2, 4))
                        .overlay(alignment: .center) {
                            if fraction > 0.15 {
                                Text(entry.phase.instruction)
                                    .font(.system(size: 8, weight: .semibold))
                                    .foregroundStyle(.black.opacity(0.65))
                                    .lineLimit(1)
                            }
                        }
                }
            }
        }
        .frame(height: 18)
    }
}

// MARK: - Custom Editor

struct CustomTechniqueEditor: View {
    @State private var draft: BreathingTechnique
    let onSave: (BreathingTechnique) -> Void
    let onCancel: () -> Void

    init(
        technique: BreathingTechnique,
        onSave: @escaping (BreathingTechnique) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _draft = State(initialValue: technique)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text("Custom technique")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)

            TextField("Name", text: $draft.name)
                .textFieldStyle(.roundedBorder)

            PhaseTimeline(pattern: draft.pattern)

            VStack(spacing: Spacing.md) {
                phaseSlider("Breathe in", value: $draft.pattern.inhale, range: BreathingLimits.inhaleRange)
                phaseSlider("Hold in", value: $draft.pattern.holdIn, range: BreathingLimits.holdRange)
                phaseSlider("Breathe out", value: $draft.pattern.exhale, range: BreathingLimits.exhaleRange)
                phaseSlider("Rest", value: $draft.pattern.holdOut, range: BreathingLimits.holdRange)

                HStack {
                    Text("Cycles")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 88, alignment: .leading)

                    Stepper(
                        "\(draft.cycleCount)",
                        value: $draft.cycleCount,
                        in: BreathingLimits.cycleCountRange
                    )
                    .foregroundStyle(.white)
                }
            }

            HStack {
                Text("Total")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                Text(DurationFormatter.mmss(draft.totalDuration))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(BrandColor.teal)
                    .monospacedDigit()
            }

            // Why the sliders stop where they do. Users hitting a limit
            // deserve a reason rather than an unexplained hard stop.
            Text("Phase lengths are limited to comfortable ranges. Long breath holds commonly cause lightheadedness, so holds cap at 10 seconds.")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            HStack {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)

                Spacer()

                Button("Save") { onSave(draft.sanitized) }
                    .buttonStyle(.borderedProminent)
                    .tint(BrandColor.teal)
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(Spacing.xl)
        .background(BrandColor.slate)
    }

    private func phaseSlider(
        _ label: String,
        value: Binding<TimeInterval>,
        range: ClosedRange<TimeInterval>
    ) -> some View {
        HStack(spacing: Spacing.md) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 88, alignment: .leading)

            Slider(value: value, in: range, step: 0.5)
                .tint(BrandColor.teal)

            Text(String(format: "%.1fs", value.wrappedValue))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
                .monospacedDigit()
                .frame(width: 40, alignment: .trailing)
        }
    }
}

// MARK: - Preview

#if DEBUG
@MainActor
private func makeBreathingPreviewCoordinator() -> BreathingCoordinator {
    BreathingCoordinator(store: InMemoryBreathingPreferencesStore())
}

#Preview("Library") {
    BreathingLibraryView(coordinator: makeBreathingPreviewCoordinator())
        .frame(width: 420, height: 720)
        .background(BrandColor.slate)
}

#Preview("Editor") {
    CustomTechniqueEditor(
        technique: .newCustom(),
        onSave: { _ in },
        onCancel: {}
    )
    .frame(width: 420, height: 520)
}
#endif
