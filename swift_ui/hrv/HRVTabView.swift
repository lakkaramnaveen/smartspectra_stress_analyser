import SwiftUI

struct HRVTabView: View {
    @ObservedObject var coordinator: HRVCoordinator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                header
                signalCard

                if let reading = coordinator.latestReading {
                    readingCard(reading)
                } else {
                    waitingCard
                }

                if coordinator.history.count >= 5 {
                    trendChart
                }

                if let r = coordinator.stressCorrelation {
                    correlationCard(r)
                }

                methodNote
            }
            .padding(Spacing.xl)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Beat variability")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)

            Text("How much the spacing between your heartbeats changes")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    // MARK: Signal

    /// Signal quality is shown above the number, not beside it.
    ///
    /// An RMSSD figure computed from a noisy interval series looks
    /// exactly as authoritative as a clean one, so the reader needs to
    /// see the caveat before the value, not after.
    private var signalCard: some View {
        HStack(spacing: Spacing.md) {
            Circle()
                .fill(coordinator.quality.color)
                .frame(width: 8, height: 8)

            Text(coordinator.quality.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))

            Spacer()

            if coordinator.sampleRateHz > 0 {
                Text(String(format: "%.0f Hz", coordinator.sampleRateHz))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
                    .help("Camera sample rate. Below 25 Hz, beat timing is too coarse to measure variability.")
            }
        }
        .padding(Spacing.md)
        .background(Color.white.opacity(0.04))
        .cornerRadius(10)
    }

    // MARK: Reading

    private func readingCard(_ reading: HRVReading) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Text(String(format: "%.0f", reading.measurement.rmssd))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()

                Text("ms")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(reading.band.label)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(reading.band.color)

                    if let percent = reading.percentFromBaseline {
                        Text(String(format: "%+.0f%% vs usual", percent))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5))
                            .monospacedDigit()
                    }
                }
            }

            Text(reading.band.note)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)

            Divider().opacity(0.12)

            HStack(spacing: Spacing.lg) {
                metric("SDNN", String(format: "%.0f ms", reading.measurement.sdnn))
                metric("Mean HR", String(format: "%.0f bpm", reading.measurement.meanBPM))
                metric("Beats", "\(reading.measurement.beatCount)")
                metric("Rejected", String(format: "%.0f%%", reading.measurement.artefactRate * 100))
            }
        }
        .padding(Spacing.lg)
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }

    private var waitingCard: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "waveform.path")
                .font(.system(size: 26))
                .foregroundStyle(.white.opacity(0.3))

            Text(
                coordinator.quality == .unusable
                    ? "Waiting for a clean enough signal"
                    : "Collecting beats…"
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.65))

            Text("Needs about 30 clean beats. Sitting still with even lighting on your face helps more than anything else.")
                .font(.system(size: 10))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(Color.white.opacity(0.03))
        .cornerRadius(12)
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
                .monospacedDigit()
        }
    }

    // MARK: Trend

    private var trendChart: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Recent readings")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)

            let values = coordinator.history.suffix(60).map(\.rmssd)
            let maxValue = values.max() ?? 1

            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(BrandColor.teal.opacity(0.75))
                        .frame(height: max(3, CGFloat(value / maxValue) * 90))
                }
            }
            .frame(height: 100, alignment: .bottom)

            if let baseline = coordinator.latestReading?.personalBaseline {
                Text(String(format: "Your usual sits around %.0f ms", baseline))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .padding(Spacing.lg)
        .background(Color.white.opacity(0.04))
        .cornerRadius(12)
    }

    // MARK: Correlation

    private func correlationCard(_ r: Double) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Against your stress readings")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)

            Text(correlationHeadline(r))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)

            Text("Both figures come from the same camera feed, so some of any apparent relationship reflects shared measurement conditions rather than physiology.")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.lg)
        .background(Color.white.opacity(0.04))
        .cornerRadius(12)
    }

    private func correlationHeadline(_ r: Double) -> String {
        let strength = CorrelationAnalyzer.strengthLabel(for: r)

        if abs(r) < 0.3 {
            return "No clear relationship between your variability and your stress readings so far (r = \(String(format: "%.2f", r)))."
        }

        return r < 0
            ? "Your variability has tended to be lower when your stress readings are higher — \(strength) relationship (r = \(String(format: "%.2f", r)))."
            : "Your variability has tended to be higher when your stress readings are higher — \(strength) relationship (r = \(String(format: "%.2f", r))). That's the opposite of the usual pattern, and worth treating cautiously."
    }

    // MARK: Method note

    private var methodNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("What this is")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))

            Text(HRVReading.disclaimer)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)

            Text("A camera samples around 30 times a second, which is coarse relative to the millisecond differences being measured. The maths corrects for this as far as it can, but readings will be noisier than a chest strap and shouldn't be used to judge your cardiac health.")
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
private func makeHRVPreviewCoordinator() -> HRVCoordinator {
    HRVCoordinator(store: InMemoryHRVStore())
}

#Preview {
    HRVTabView(coordinator: makeHRVPreviewCoordinator())
        .frame(width: 400, height: 720)
        .background(BrandColor.slate)
}
#endif
