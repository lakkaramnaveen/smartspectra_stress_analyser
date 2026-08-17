import SwiftUI

struct EnvironmentSectionView: View {
    @ObservedObject var coordinator: EnvironmentCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            header
            noiseConsentCard
            liveReadingsCard

            if !coordinator.associations.isEmpty {
                associationsSection
            }

            unavailableNote
        }
        .task { await coordinator.refresh() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Environment")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
            Text("Lighting and noise, and how they line up with your readings")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    // MARK: - Noise consent

    /// Leads with noise specifically, not lighting — lighting reuses
    /// camera frames the app already has permission for and needs no
    /// disclosure of its own; noise is a new sensor and a new
    /// permission, and gets the same up-front treatment every other
    /// opt-in data source in this app gets.
    private var noiseConsentCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Toggle(isOn: Binding(
                get: { coordinator.noiseMonitoringEnabled },
                set: { coordinator.setNoiseMonitoringEnabled($0) }
            )) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "mic")
                        .foregroundStyle(BrandColor.amber)
                    Text("Track ambient noise level")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }
            .toggleStyle(.switch)
            .tint(BrandColor.primaryBlue)

            Text("Off by default, and needs microphone access the first time it's turned on. Only a single loudness number is ever computed — nothing is recorded, transcribed, or stored, and there's no code path in this feature that could save or send actual sound. Like app tracking, this only runs during an active session, never in the background.")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)

            Text("Lighting doesn't have a toggle — it's extra analysis of camera frames already being captured for the core feature, so nothing new is being observed.")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.5))
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

    // MARK: - Live readings

    private var liveReadingsCard: some View {
        HStack(spacing: Spacing.lg) {
            readingTile(
                icon: "light.max",
                label: "Lighting",
                value: coordinator.currentBrightness,
                color: BrandColor.amber
            )
            if coordinator.noiseMonitoringEnabled {
                readingTile(
                    icon: "waveform",
                    label: "Noise",
                    value: coordinator.currentNoiseLevel,
                    color: BrandColor.teal
                )
            }
        }
    }

    private func readingTile(icon: String, label: String, value: Double?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 11, weight: .semibold)).foregroundStyle(color)
                Text(label).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
            }
            if let value {
                Text(String(format: "%.0f%%", value * 100))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            } else {
                Text("—")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .background(Color.white.opacity(0.04))
        .cornerRadius(10)
    }

    // MARK: - Associations

    private var associationsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("What the pattern shows")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)

            ForEach(coordinator.associations, id: \.dimension) { association in
                associationCard(association)
            }

            Text("These compare your readings during the dimmest or quietest third of moments against the brightest or loudest third — an association from your own data, not a claim that either one causes the other.")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func associationCard(_ association: EnvironmentAssociation) -> some View {
        let delta = association.stressInUpperThird - association.stressInLowerThird
        let direction = association.dimension == .lighting
            ? (delta > 0 ? "Darker moments have run a bit calmer" : "Brighter moments have run a bit calmer")
            : (delta > 0 ? "Quieter moments have run a bit calmer" : "Louder moments haven't shown a clear cost")

        return VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: association.dimension.icon)
                    .foregroundStyle(BrandColor.teal)
                Text(association.dimension.label)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
            }

            Text(abs(delta) > 0.03 ? direction : "No clear difference yet")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))

            Text(String(
                format: "%.0f%% avg. in the lower third · %.0f%% avg. in the upper third · %d readings",
                association.stressInLowerThird * 100,
                association.stressInUpperThird * 100,
                association.sampleCount
            ))
            .font(.system(size: 10))
            .foregroundStyle(.white.opacity(0.5))
        }
        .padding(Spacing.lg)
        .background(Color.white.opacity(0.04))
        .cornerRadius(12)
    }

    // MARK: - What isn't available

    /// States plainly that room temperature isn't part of this, and
    /// why — a Mac has no sensor a third-party app can read for that,
    /// and the machine's own internal thermal sensors measure the
    /// computer's heat, not the room's.
    private var unavailableNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("What this can't do")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))

            Text("There's no room-temperature reading here, and there isn't a way to add one. A Mac has no ambient temperature sensor a third-party app can read — its internal thermal sensors measure the computer's own heat, which has nothing to do with the room it's sitting in.")
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
private func makeEnvironmentPreviewCoordinator() -> EnvironmentCoordinator {
    EnvironmentCoordinator(
        store: InMemoryEnvironmentStore(state: EnvironmentState(brightnessSamples: [], noiseSamples: [], noiseMonitoringEnabled: true)),
        sessionStore: InMemorySessionStore()
    )
}

#Preview {
    ScrollView {
        EnvironmentSectionView(coordinator: makeEnvironmentPreviewCoordinator())
            .padding(Spacing.xl)
    }
    .frame(width: 420, height: 780)
    .background(BrandColor.slate)
}
#endif
