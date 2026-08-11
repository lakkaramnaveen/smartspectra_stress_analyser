import SwiftUI

// MARK: - Dashboard

struct InsightsDashboardView: View {
    @StateObject private var viewModel: InsightsViewModel

    init(store: SessionStoring? = nil) {
        _viewModel = StateObject(wrappedValue: InsightsViewModel(store: store))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                header

                switch viewModel.state {
                case .idle, .loading:
                    loadingState
                case .needsMoreData(let recorded, let needed):
                    needsMoreDataState(recorded: recorded, needed: needed)
                case .ready:
                    readyContent
                }
            }
            .padding(Spacing.xl)
        }
        .task { await viewModel.refresh() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Insights")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)

            Text("Patterns across your recorded sessions")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    // MARK: - States

    private var loadingState: some View {
        HStack(spacing: Spacing.md) {
            ProgressView().controlSize(.small)
            Text("Analysing your sessions…")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 40)
    }

    private func needsMoreDataState(recorded: Int, needed: Int) -> some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 30))
                .foregroundStyle(.white.opacity(0.35))

            Text("Not enough data yet")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white.opacity(0.8))

            Text("You've recorded \(recorded) of \(needed) sessions. Patterns drawn from fewer than that would be more noise than signal, so nothing is shown until there's enough to be meaningful.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)

            ProgressView(value: Double(recorded), total: Double(needed))
                .tint(BrandColor.teal)
                .frame(maxWidth: 220)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    @ViewBuilder
    private var readyContent: some View {
        if viewModel.insights.isEmpty {
            Text("No clear patterns have emerged yet. That's a normal result — it usually means your sessions have been fairly consistent.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 20)
        } else {
            VStack(alignment: .leading, spacing: Spacing.md) {
                ForEach(viewModel.insights) { insight in
                    InsightCard(insight: insight)
                }
            }
        }

        if !viewModel.aggregates.hourBuckets.isEmpty {
            HourOfDayHeatmap(buckets: viewModel.aggregates.hourBuckets)
        }

        if viewModel.aggregates.weeklyTrend.count >= 2 {
            WeeklyTrendChart(points: viewModel.aggregates.weeklyTrend)
        }

        methodologyNote
    }

    /// Sits at the bottom of the dashboard permanently. Someone acting on
    /// these observations deserves to know how they were produced.
    private var methodologyNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("How these are produced")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))

            Text("These are averages and correlations calculated from your own recorded sessions — not predictions, and not medical assessment. Patterns from a small number of sessions can easily reflect coincidence, which is why each card shows how much data sits behind it.")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.md)
        .background(Color.white.opacity(0.03))
        .cornerRadius(8)
    }
}

// MARK: - Insight Card

struct InsightCard: View {
    let insight: Insight

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: insight.category.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(insight.category.color)

                Text(insight.category.label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))

                Spacer()

                confidenceBadge
            }

            Text(insight.headline)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            Text(insight.detail)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)

            if let suggestion = insight.suggestion {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "lightbulb")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(BrandColor.amber)
                    Text(suggestion)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 2)
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(insight.category.color.opacity(0.2), lineWidth: 1)
        )
        .cornerRadius(12)
    }

    private var confidenceBadge: some View {
        HStack(spacing: 4) {
            Text(insight.confidence.label)
            Text("·")
            Text("\(insight.sessionCount) sessions")
        }
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(insight.confidence.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(insight.confidence.color.opacity(0.15), in: Capsule())
    }
}

// MARK: - Hour Heatmap

struct HourOfDayHeatmap: View {
    let buckets: [HourBucket]

    private var maxStress: Double {
        buckets.map(\.averageStress).max() ?? 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Average stress by hour")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)

            VStack(spacing: 3) {
                ForEach(buckets) { bucket in
                    HStack(spacing: Spacing.sm) {
                        Text(hourLabel(bucket.hour))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.5))
                            .frame(width: 46, alignment: .trailing)

                        GeometryReader { proxy in
                            let ratio = maxStress > 0 ? bucket.averageStress / maxStress : 0
                            let barWidth = proxy.size.width * CGFloat(ratio)

                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.white.opacity(0.05))

                                RoundedRectangle(cornerRadius: 3)
                                    .fill(StressLevel.classify(bucket.averageStress).color.opacity(0.8))
                                    .frame(width: max(barWidth, 2))
                            }
                        }
                        .frame(height: 14)

                        Text(String(format: "%.0f%%", bucket.averageStress * 100))
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(width: 32, alignment: .trailing)
                    }
                }
            }
        }
        .padding(Spacing.lg)
        .background(Color.white.opacity(0.04))
        .cornerRadius(12)
    }

    private func hourLabel(_ hour: Int) -> String {
        switch hour {
        case 0: return "12 AM"
        case 12: return "12 PM"
        case 1..<12: return "\(hour) AM"
        default: return "\(hour - 12) PM"
        }
    }
}

// MARK: - Weekly Trend

struct WeeklyTrendChart: View {
    let points: [WeeklyTrendPoint]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Weekly average")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)

            HStack(alignment: .bottom, spacing: Spacing.sm) {
                ForEach(points) { point in
                    VStack(spacing: 4) {
                        Text(String(format: "%.0f", point.averageStress * 100))
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.6))

                        RoundedRectangle(cornerRadius: 4)
                            .fill(StressLevel.classify(point.averageStress).color.opacity(0.75))
                            .frame(height: max(6, CGFloat(point.averageStress) * 90))

                        Text(weekLabel(point.weekStart))
                            .font(.system(size: 8))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 130, alignment: .bottom)
        }
        .padding(Spacing.lg)
        .background(Color.white.opacity(0.04))
        .cornerRadius(12)
    }

    private func weekLabel(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }
}

// MARK: - Preview

#if DEBUG
private func makeInsightsPreviewStore() -> SessionStoring {
    let store = InMemorySessionStore()
    let calendar = Calendar.current

    for dayOffset in 0..<12 {
        guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) else { continue }

        for hour in [9, 14, 19] {
            guard let start = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) else { continue }

            // Afternoons deliberately run hotter so the time-of-day
            // insight has something to find.
            let base: Double = hour == 14 ? 0.62 : 0.38

            let snapshots: [SessionSnapshot] = (0..<90).map { i in
                let jitter = Double.random(in: -0.06...0.06)
                return SessionSnapshot(
                    timestamp: start.addingTimeInterval(Double(i)),
                    stressScore: min(max(base + jitter, 0), 1),
                    heartRate: 68 + base * 30 + Double.random(in: -4...4),
                    breathingRate: 12 + base * 8,
                    eda: 0.01 + base * 0.05,
                    emotionalState: "Focused",
                    gazeConfidence: 0.85
                )
            }

            var recording = SessionRecording(
                startedAt: start,
                difficulty: "medium",
                snapshots: snapshots
            )
            recording.endedAt = start.addingTimeInterval(90)
            try? store.save(recording)
        }
    }

    return store
}

#Preview {
    InsightsDashboardView(store: makeInsightsPreviewStore())
        .frame(width: 420, height: 700)
        .background(BrandColor.slate)
}
#endif
