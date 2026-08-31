import SwiftUI

// MARK: - Trend Pill

/// Compact always-visible trend indicator, sized to sit alongside the
/// existing stress-level pill in the workspace status bar.
struct StressTrendPill: View {
    let forecast: StressForecast

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: forecast.direction.icon)
                .font(.system(size: 10, weight: .bold))

            Text(forecast.direction.label)
                .font(.caption.weight(.semibold))

            if let eta = forecast.formattedTimeToThreshold {
                Text("· \(eta)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
        .foregroundStyle(forecast.direction.color)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(forecast.direction.color.opacity(0.18), in: Capsule())
    }
}

// MARK: - Forecast Card

/// Fuller breakdown for the Stress tab: direction, rate, fit quality,
/// and the supportive message.
struct StressForecastCard: View {
    let forecast: StressForecast

    /// Stress-score change per minute, which is a far more legible unit
    /// than per-second for a human reading a card.
    private var percentPerMinute: Double {
        forecast.slopePerSecond * 60 * 100
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(forecast.direction.color)

                Text("Trend Forecast")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)

                Spacer()

                Text(forecast.direction.label)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(forecast.direction.color)
            }

            Text(forecast.message)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)

            Divider().opacity(0.12)

            HStack(spacing: Spacing.lg) {
                metric(
                    label: "Rate",
                    value: String(format: "%+.1f%%/min", percentPerMinute)
                )
                metric(
                    label: "Fit",
                    value: String(format: "%.0f%%", forecast.confidence * 100)
                )
                metric(
                    label: "Samples",
                    value: "\(forecast.sampleCount)"
                )
            }

            // Honest about what this number is. The forecast is a
            // straight-line extrapolation, and saying so in the UI is
            // cheaper than a user learning it the hard way when the
            // estimate misses.
            Text("Estimated by extending the recent trend — an indication, not a prediction.")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.45))
        }
        .padding(Spacing.lg)
        .background(Color.white.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .cornerRadius(12)
    }

    private func metric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
        }
    }
}

// MARK: - Alert Banner

/// Dismissible in-app banner. Shown regardless of notification
/// permissions, so the feature works even if the user declined the
/// system prompt.
struct StressAlertBanner: View {
    let alert: StressAlert
    let onDismiss: () -> Void
    let onStartBreathing: () -> Void

    private var accentColor: Color {
        switch alert.kind {
        case .risingTrend: return BrandColor.amber
        case .recovered: return BrandColor.mint
        }
    }

    private var iconName: String {
        switch alert.kind {
        case .risingTrend: return "arrow.up.right.circle.fill"
        case .recovered: return "checkmark.circle.fill"
        }
    }

    private var showsBreathingAction: Bool {
        if case .risingTrend = alert.kind { return true }
        return false
    }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: iconName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(accentColor)

            VStack(alignment: .leading, spacing: 4) {
                Text(alert.title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)

                Text(alert.body)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)

                if showsBreathingAction {
                    Button(action: onStartBreathing) {
                        Text("Start breathing")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.borderless)
                    .tint(accentColor)
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
            .accessibilityLabel("Dismiss")
        }
        .padding(Spacing.lg)
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(accentColor.opacity(0.4), lineWidth: 1)
        )
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
    }
}

// MARK: - Previews

#if DEBUG
private func makeRisingForecast() -> StressForecast {
    StressForecast(
        currentScore: 0.62,
        direction: .rising,
        slopePerSecond: 0.0018,
        confidence: 0.71,
        timeToThreshold: 183,
        sampleCount: 96
    )
}

#Preview("Forecast Card") {
    StressForecastCard(forecast: makeRisingForecast())
        .padding()
        .frame(width: 360)
        .background(BrandColor.slate)
}

#Preview("Alert Banner") {
    StressAlertBanner(
        alert: StressAlert(
            kind: .risingTrend(etaSeconds: 183),
            title: "Stress is climbing",
            body: "On the current trend you'd reach your threshold in ~3 min. A short breathing break now would help.",
            raisedAt: Date()
        ),
        onDismiss: {},
        onStartBreathing: {}
    )
    .padding()
    .frame(width: 400)
    .background(BrandColor.slate)
}
#endif
