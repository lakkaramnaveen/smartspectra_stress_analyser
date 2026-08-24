import SwiftUI

struct HealthSyncView: View {
    @ObservedObject var coordinator: HealthSyncCoordinator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                header
                platformNotice
                statusCard
                whatIsCaptured
                sleepAndStepsNote
            }
            .padding(Spacing.xl)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Health Export")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)

            Text("Prepares your data for Apple Health — doesn't write to it directly")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    /// Leads the screen rather than sitting in a footnote. HealthKit's
    /// absence on macOS is the one fact that governs everything else
    /// here, so it comes before any numbers or buttons, not after them.
    private var platformNotice: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(BrandColor.amber)
                Text("HealthKit isn't available on macOS")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
            }

            Text("Apple restricts HealthKit to iOS, watchOS, and visionOS. There is no framework-level way for a Mac app to write into, or read from, the Health app — not a limited version, not a workaround. Nothing on this screen does that.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)

            Text("What this actually does: buffer your heart rate, breathing rate, and mindful-practice sessions, mapped to the exact identifiers Health itself uses, and let you export them as a file. Getting that file into Health for real needs a separate iOS app with HealthKit permission — this screen can prepare the data, but only an iOS app can deliver it.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.lg)
        .background(BrandColor.amber.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(BrandColor.amber.opacity(0.3), lineWidth: 1)
        )
        .cornerRadius(12)
    }

    // MARK: Status

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            StatsRow(
                icon: "tray.full",
                label: "Buffered readings",
                value: "\(coordinator.pendingSampleCount)",
                color: BrandColor.teal
            )
            StatsRow(
                icon: "shippingbox",
                label: "Batches queued",
                value: "\(coordinator.pendingBatches.count)",
                color: BrandColor.lightBlue
            )
            StatsRow(
                icon: "clock",
                label: "Last export",
                value: coordinator.lastExportedAt.map {
                    $0.formatted(date: .abbreviated, time: .shortened)
                } ?? "Never",
                color: BrandColor.mediumGray
            )

            Button(action: { coordinator.exportNow() }) {
                Group {
                    if coordinator.isExporting {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Export queued data", systemImage: "square.and.arrow.up")
                            .font(.callout.weight(.semibold))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(10)
            }
            .buttonStyle(.borderedProminent)
            .tint(BrandColor.primaryBlue)
            .disabled(coordinator.pendingBatches.isEmpty || coordinator.isExporting)
            .padding(.top, Spacing.xs)
        }
        .padding(Spacing.lg)
        .background(Color.white.opacity(0.04))
        .cornerRadius(12)
    }

    // MARK: Mapping

    private var whatIsCaptured: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("What's captured")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)

            mappingRow(
                icon: "heart.fill",
                label: "Heart rate",
                identifier: HealthIdentifier.heartRate,
                color: BrandColor.coral
            )
            mappingRow(
                icon: "wind",
                label: "Breathing rate",
                identifier: HealthIdentifier.respiratoryRate,
                color: BrandColor.mint
            )
            mappingRow(
                icon: "brain.head.profile",
                label: "Mindful sessions",
                identifier: HealthIdentifier.mindfulSession,
                color: BrandColor.primaryBlue
            )

            Text("Buffered every few seconds while a session runs and grouped into a batch roughly every five minutes, or immediately when you tap export.")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.lg)
        .background(Color.white.opacity(0.04))
        .cornerRadius(12)
    }

    private func mappingRow(icon: String, label: String, identifier: String, color: Color) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 18)

            Text(label)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))

            Spacer()

            Text(identifier)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
                .lineLimit(1)
        }
    }

    // MARK: Sleep / Steps note

    private var sleepAndStepsNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("About reading steps and sleep")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))

            Text("Reading data back from Health has the identical platform limitation — there's no way for this app to see it, in either direction. That's the reason the Rest tab asks you to log sleep yourself instead of pulling it in automatically: it's a direct substitute for the HealthKit read this feature can't do, not an oversight.")
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
private func makeHealthSyncPreviewCoordinator() -> HealthSyncCoordinator {
    let batches = [
        HealthSyncBatch(
            id: UUID(),
            createdAt: Date(),
            heartRateSamples: (0..<12).map {
                HeartRateSample(bpm: 68 + Double($0), timestamp: Date().addingTimeInterval(Double($0) * 5))
            },
            respiratoryRateSamples: (0..<8).map {
                RespiratoryRateSample(breathsPerMinute: 14, timestamp: Date().addingTimeInterval(Double($0) * 10))
            },
            mindfulIntervals: [
                MindfulInterval(start: Date().addingTimeInterval(-300), end: Date().addingTimeInterval(-120), source: "4-7-8")
            ]
        )
    ]
    return HealthSyncCoordinator(store: InMemoryHealthSyncStore(batches: batches))
}

#Preview {
    HealthSyncView(coordinator: makeHealthSyncPreviewCoordinator())
        .frame(width: 420, height: 760)
        .background(BrandColor.slate)
}
#endif
