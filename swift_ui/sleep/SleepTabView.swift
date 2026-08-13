import SwiftUI

// MARK: - Tab

struct SleepTabView: View {
    @ObservedObject var coordinator: SleepCoordinator

    @State private var hours: Double = 7.5
    @State private var quality: RestQuality = .okay

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                header
                logCard
                associationCard

                if coordinator.dayparts.contains(where: { $0.sampleCount >= DaypartStress.minimumSamples }) {
                    daypartCard
                }

                if !coordinator.recent().isEmpty {
                    recentNights
                }

                sourceNote
            }
            .padding(Spacing.xl)
        }
        .task { await coordinator.analyse() }
        .onAppear {
            if let existing = coordinator.todaysEntry {
                hours = existing.hours
                quality = existing.quality
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Rest")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)

            Text("How your nights line up with your readings")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    // MARK: Log

    /// Morning log.
    ///
    /// No streak, no score, no "you missed yesterday". Sleep tracking
    /// reliably makes some people anxious about sleep, which then makes
    /// sleep worse — so nothing here rewards logging every day or
    /// penalises gaps.
    private var logCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Text(coordinator.hasLoggedToday ? "This morning" : "How did you sleep?")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)

                Spacer()

                if coordinator.hasLoggedToday {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(BrandColor.mint)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Roughly how long")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    Text(formattedHours)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(BrandColor.teal)
                        .monospacedDigit()
                }

                Slider(
                    value: $hours,
                    in: SleepEntry.hoursRange,
                    step: 0.25
                )
                .tint(BrandColor.teal)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("How rested do you feel?")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))

                HStack(spacing: Spacing.sm) {
                    ForEach(RestQuality.allCases, id: \.self) { option in
                        qualityButton(option)
                    }
                }
            }

            Button {
                coordinator.log(hours: hours, quality: quality)
            } label: {
                Text(coordinator.hasLoggedToday ? "Update" : "Save")
                    .font(.callout.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(10)
                    .background(BrandColor.primaryBlue)
                    .foregroundStyle(.white)
                    .cornerRadius(9)
                    .contentShape(RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain)
        }
        .padding(Spacing.lg)
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }

    private var formattedHours: String {
        let whole = Int(hours)
        let minutes = Int((hours - Double(whole)) * 60)
        return minutes == 0 ? "\(whole)h" : "\(whole)h \(minutes)m"
    }

    private func qualityButton(_ option: RestQuality) -> some View {
        let isSelected = quality == option

        return Button {
            quality = option
        } label: {
            VStack(spacing: 4) {
                Image(systemName: option.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(height: 18)
                Text(option.label)
                    .font(.system(size: 9, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .foregroundStyle(isSelected ? .white : .white.opacity(0.55))
            .background(isSelected ? option.color.opacity(0.28) : Color.white.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(isSelected ? option.color.opacity(0.6) : .clear, lineWidth: 1)
            )
            .cornerRadius(9)
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
    }

    // MARK: Association

    private var associationCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(coordinator.association.color)

                Text("Rest and your readings")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)

                Spacer()

                if coordinator.isAnalysing {
                    ProgressView().controlSize(.mini)
                }
            }

            Text(coordinator.association.headline)
                .font(.callout.weight(.semibold))
                .foregroundStyle(coordinator.association.color)
                .fixedSize(horizontal: false, vertical: true)

            if let detail = coordinator.association.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Caveat sits with the finding, not behind a disclosure.
            Text(coordinator.association.caveat)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)

            if coordinator.association.direction == .insufficientData {
                ProgressView(
                    value: Double(coordinator.association.nightsCompared),
                    total: Double(SleepAssociation.minimumNights)
                )
                .tint(BrandColor.teal)
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.lg)
        .background(Color.white.opacity(0.04))
        .cornerRadius(12)
    }

    // MARK: Dayparts

    private var daypartCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Across the day")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)

            ForEach(coordinator.dayparts) { part in
                daypartRow(part)
            }
        }
        .padding(Spacing.lg)
        .background(Color.white.opacity(0.04))
        .cornerRadius(12)
    }

    private func daypartRow(_ part: DaypartStress) -> some View {
        let hasEnough = part.sampleCount >= DaypartStress.minimumSamples

        return HStack(spacing: Spacing.md) {
            Image(systemName: part.part.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(hasEnough ? BrandColor.lightBlue : .white.opacity(0.25))
                .frame(width: 20)

            Text(part.part.label)
                .font(.caption)
                .foregroundStyle(.white.opacity(hasEnough ? 0.8 : 0.35))
                .frame(width: 66, alignment: .leading)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.06))

                    if hasEnough {
                        Capsule()
                            .fill(StressLevel.classify(part.averageStress).color.opacity(0.8))
                            .frame(width: proxy.size.width * CGFloat(part.averageStress))
                    }
                }
            }
            .frame(height: 12)

            Text(hasEnough ? String(format: "%.0f%%", part.averageStress * 100) : "—")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(hasEnough ? 0.7 : 0.3))
                .frame(width: 34, alignment: .trailing)
        }
    }

    // MARK: Recent nights

    private var recentNights: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Recent nights")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)

            ForEach(coordinator.recent()) { entry in
                HStack(spacing: Spacing.md) {
                    Image(systemName: entry.quality.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(entry.quality.color)
                        .frame(width: 18)

                    Text(entry.forDay.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))

                    Spacer()

                    Text(String(format: "%.1fh", entry.hours))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                        .monospacedDigit()

                    Text(entry.quality.label)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(entry.quality.color)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, Spacing.md)
                .background(Color.white.opacity(0.03))
                .cornerRadius(8)
                .contextMenu {
                    Button(role: .destructive) {
                        coordinator.delete(entry)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
    }

    // MARK: Source note

    /// Explains why this is typed in rather than read automatically —
    /// otherwise the obvious question is "why doesn't this just use my
    /// Apple Watch?"
    private var sourceNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Why you're typing this in")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))

            Text("HealthKit isn't available on macOS, so there's no way for a Mac app to read sleep from a Watch or phone. A rough figure typed in each morning is enough for this to be useful — precision isn't the point.")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)

            Text("This isn't sleep tracking or medical assessment. If sleep is a persistent problem, that's worth raising with a doctor rather than an app.")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.md)
        .background(Color.white.opacity(0.03))
        .cornerRadius(8)
    }
}

#if DEBUG
@MainActor
private func makeSleepPreviewCoordinator() -> SleepCoordinator {
    let calendar = Calendar.current
    let entries: [SleepEntry] = (1...12).compactMap { offset in
        guard let day = calendar.date(byAdding: .day, value: -offset, to: Date()) else { return nil }
        return SleepEntry(
            forDay: day,
            hours: Double.random(in: 5.5...8.5),
            quality: RestQuality.allCases.randomElement() ?? .okay
        )
    }

    return SleepCoordinator(
        store: InMemorySleepStore(entries: entries),
        sessionStore: InMemorySessionStore()
    )
}

#Preview {
    SleepTabView(coordinator: makeSleepPreviewCoordinator())
        .frame(width: 400, height: 760)
        .background(BrandColor.slate)
}
#endif
