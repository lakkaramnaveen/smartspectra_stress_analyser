import SwiftUI

struct AppUsageView: View {
    @ObservedObject var coordinator: AppUsageCoordinator
    @ObservedObject var focus: FocusCoordinator

    @State private var confirmingClear = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                header
                consentCard
                statusCard

                if coordinator.isEnabled {
                    if coordinator.associations.isEmpty {
                        emptyState
                    } else {
                        associationsSection
                    }
                }

                blockingNote
            }
            .padding(Spacing.xl)
        }
        .task { await coordinator.refresh() }
        .alert("Clear app-usage history?", isPresented: $confirmingClear) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) { coordinator.clearHistory() }
        } message: {
            Text("This deletes every recorded app-focus entry. It can't be undone.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Triggers")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
            Text("Which apps tend to be open when your stress runs higher")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    // MARK: - Consent

    /// Leads the view, and is the most important disclosure in this
    /// whole app. This is the one feature here that observes something
    /// other than Composure's own data — what else the person is doing
    /// on their Mac — and that deserves being told plainly, up front,
    /// every time this tab is opened.
    private var consentCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "eye.slash")
                    .foregroundStyle(BrandColor.amber)
                Text("Off by default — here's exactly what this does")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
            }

            Text("When enabled, this records which app is in front and for how long, only while a Composure session is running — never in the background otherwise. It never sees window titles, documents, URLs, messages, or notification content. That's not a setting; there's no public way for any app on this Mac to see that about another app, so it's simply never captured.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)

            Text("Entries older than 30 days are removed automatically. You can also clear everything at any time below.")
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

    // MARK: - Status

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Toggle(isOn: Binding(
                get: { coordinator.isEnabled },
                set: { coordinator.setEnabled($0) }
            )) {
                Text("Track app usage during sessions")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .toggleStyle(.switch)
            .tint(BrandColor.primaryBlue)

            if coordinator.isEnabled {
                StatsRow(
                    icon: "clock",
                    label: "Tracked so far",
                    value: DurationFormatter.mmss(coordinator.totalTrackedMinutes * 60),
                    color: BrandColor.teal
                )

                Button("Clear history", role: .destructive) {
                    confirmingClear = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(Spacing.lg)
        .background(Color.white.opacity(0.04))
        .cornerRadius(12)
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 26))
                .foregroundStyle(.white.opacity(0.3))
            Text("Not enough data yet")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white.opacity(0.75))
            Text("Run a few more sessions with this on and patterns will start showing up here.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(Color.white.opacity(0.03))
        .cornerRadius(12)
    }

    // MARK: - Associations

    private var associationsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("What the pattern shows")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)

            ForEach(coordinator.associations) { association in
                AssociationRow(association: association)
            }

            if let top = coordinator.associations.first, top.deltaPoints > 0.05 {
                reflectionCard(for: top)
            }

            Text("These are averages while each app happened to be in front, compared to your overall baseline — not a claim that any app is the reason. Opening an app can just as easily be a response to stress that had already started.")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func reflectionCard(for association: AppStressAssociation) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Worth trying next time")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)

            Text("Next time you notice yourself reaching for \(association.appName) and feeling keyed up, a short focus block might create some breathing room before diving in.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)

            Button("Start a focus block") {
                focus.start()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(BrandColor.primaryBlue)
        }
        .padding(Spacing.lg)
        .background(Color.white.opacity(0.04))
        .cornerRadius(12)
    }

    // MARK: - Why no blocking

    private var blockingNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Why this doesn't block apps")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))

            Text("There's no macOS equivalent of iOS's Screen Time tools that lets one app restrict another. The only mechanism that exists — forcibly closing or hiding an app — can cause real data loss and isn't something software should do on its own based on a camera-derived reading, which can read \"stressed\" from something as ordinary as bad lighting or moving your head.")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)

            Text("With more than one person able to use this Mac, a blocking feature is also exactly the kind of thing that could be turned against someone else's profile rather than used on your own. This app doesn't build that capability at all.")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.md)
        .background(Color.white.opacity(0.03))
        .cornerRadius(8)
    }
}

// MARK: - Row

private struct AssociationRow: View {
    let association: AppStressAssociation

    var body: some View {
        HStack(spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(association.appName)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                Text("\(association.sessionCount) sessions · \(Int(association.totalMinutes)) min · \(association.confidence.label)")
                    .font(.system(size: 10))
                    .foregroundStyle(association.confidence.color)
            }

            Spacer()

            Text(String(format: "%+.0f pts", association.deltaPoints * 100))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(association.deltaPoints > 0 ? BrandColor.amber : BrandColor.mint)
                .monospacedDigit()
        }
        .padding(Spacing.md)
        .background(Color.white.opacity(0.04))
        .cornerRadius(10)
    }
}

#if DEBUG
@MainActor
private func makeAppUsagePreviewCoordinator() -> AppUsageCoordinator {
    AppUsageCoordinator(
        store: InMemoryAppUsageStore(state: AppUsageState(sessions: [], isEnabled: true)),
        sessionStore: InMemorySessionStore()
    )
}

#Preview {
    AppUsageView(
        coordinator: makeAppUsagePreviewCoordinator(),
        focus: FocusCoordinator()
    )
    .frame(width: 420, height: 780)
    .background(BrandColor.slate)
}
#endif
