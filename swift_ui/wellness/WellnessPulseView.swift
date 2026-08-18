import SwiftUI

struct WellnessPulseView: View {
    @ObservedObject var coordinator: WellnessPulseCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            scopeNotice

            Toggle(isOn: Binding(
                get: { coordinator.isEnabled },
                set: { coordinator.setEnabled($0) }
            )) {
                Text("Enable wellness pulse")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .toggleStyle(.switch)
            .tint(BrandColor.primaryBlue)

            if coordinator.isEnabled {
                bandCard
            }
        }
        .padding(Spacing.xl)
        .onAppear { if coordinator.isEnabled { coordinator.refresh() } }
    }

    /// Leads the view. What this deliberately doesn't do matters as much
    /// as what it does — someone landing on a tab called "Wellness
    /// Pulse" inside a workplace context needs that stated plainly
    /// before anything else.
    private var scopeNotice: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "building.2")
                    .foregroundStyle(BrandColor.amber)
                Text("What this is, and isn't")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
            }

            Text("This exports one coarse band — Low, Moderate, or High — from your own last seven days. Nothing more precise than that ever leaves this device through this feature: no name, no raw score, no session times.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)

            Text("There's no dashboard, no aggregation across people, and no way for anyone — including an employer — to see this unless you personally hand them the file. Composure doesn't operate any server this connects to, doesn't compare teams or departments, and makes no compliance claim about how an organization handles what you choose to share.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)

            Text("If an employer asks you to install monitoring software, that's worth treating as a real decision, not a formality — this exists for people who want to voluntarily share a single number with their own wellness program, not as infrastructure for one.")
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

    private var bandCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            if let band = coordinator.currentBand {
                HStack(spacing: Spacing.sm) {
                    Circle().fill(band.color).frame(width: 10, height: 10)
                    Text(band.label)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                }
                Text("Based on your last 7 days.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            } else {
                Text("Not enough recent sessions to compute a band yet.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }

            Button("Export") {
                coordinator.export()
            }
            .buttonStyle(.borderedProminent)
            .tint(BrandColor.primaryBlue)
            .disabled(coordinator.currentBand == nil)

            if let exported = coordinator.lastExportedAt {
                Text("Last exported \(exported.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .padding(Spacing.lg)
        .background(Color.white.opacity(0.04))
        .cornerRadius(12)
    }
}

#if DEBUG
#Preview {
    WellnessPulseView(
        coordinator: WellnessPulseCoordinator(
            store: InMemoryWellnessPulseStore(),
            sessionStore: InMemorySessionStore()
        )
    )
    .frame(width: 420, height: 500)
    .background(BrandColor.slate)
}
#endif
