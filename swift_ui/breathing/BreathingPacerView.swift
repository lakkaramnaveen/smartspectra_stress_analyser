import SwiftUI

/// Guided breathing overlay, driven by whichever technique was started.
///
/// Rewritten from the original single-pattern version: phase sequencing
/// now lives in `BreathingSessionEngine`, so this file is purely
/// presentation and works unchanged for two-phase, three-phase, and
/// four-phase techniques.
struct BreathingPacerView: View {
    let technique: BreathingTechnique
    let onDismiss: () -> Void
    let onCompleted: (BreathingTechnique) -> Void

    @EnvironmentObject private var model: AppModel
    @StateObject private var engine = BreathingSessionEngine()

    @State private var orbScale: CGFloat = 0.55
    @State private var orbOpacity: Double = 0.35

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
                .opacity(0.94)

            VStack(spacing: Spacing.xl) {
                header
                orb
                cycleProgress
                liveVitals
                footer
            }
            .padding(Spacing.xxl)
            .frame(maxWidth: 520)
        }
        .onAppear {
            engine.onCompleted = { completed in
                onCompleted(completed)
                // Brief pause on the completion state before dismissing,
                // so finishing registers rather than the overlay simply
                // vanishing mid-breath.
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    onDismiss()
                }
            }
            engine.start(technique)
        }
        .onDisappear { engine.stop() }
        .onChange(of: engine.currentPhase) { _, phase in
            withAnimation(.easeInOut(duration: engine.phaseDuration)) {
                orbScale = phase.orbScale
                orbOpacity = phase.orbOpacity
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 6) {
            Text(technique.name)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)

            Text(technique.pattern.notation)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(BrandColor.teal)
                .monospacedDigit()
        }
    }

    // MARK: - Orb

    private var orb: some View {
        ZStack {
            Circle()
                .fill(BrandColor.teal.opacity(0.30))
                .frame(width: 280, height: 280)
                .blur(radius: 30)
                .scaleEffect(orbScale * 0.95)

            Circle()
                .fill(BrandColor.mint.opacity(0.45))
                .frame(width: 200, height: 200)
                .blur(radius: 16)
                .scaleEffect(orbScale)

            Circle()
                .stroke(BrandColor.teal.opacity(0.6), lineWidth: 2)
                .frame(width: 168, height: 168)

            VStack(spacing: 8) {
                Text(engine.currentPhase.instruction)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .contentTransition(.opacity)

                if engine.phaseDuration > 0 {
                    Text("\(Int(engine.phaseDuration.rounded()))s")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                        .monospacedDigit()
                }
            }
        }
        .opacity(orbOpacity + 0.4)
        .frame(height: 300)
    }

    // MARK: - Cycle progress

    private var cycleProgress: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Cycle \(min(engine.completedCycles + 1, engine.totalCycles)) of \(engine.totalCycles)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
                Text("\(Int(engine.cycleProgress * 100))%")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(BrandColor.teal)
                    .monospacedDigit()
            }

            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                GeometryReader { proxy in
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [BrandColor.mint, BrandColor.teal],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: proxy.size.width * CGFloat(engine.cycleProgress))
                }
            }
            .frame(height: 6)
            .animation(.easeOut(duration: 0.4), value: engine.cycleProgress)
        }
    }

    // MARK: - Live vitals

    private var liveVitals: some View {
        HStack(spacing: Spacing.md) {
            MetricBadge(
                icon: "heart.fill",
                value: model.vitalsDisplay.pulseBPM,
                unit: "bpm",
                color: BrandColor.coral
            )
            MetricBadge(
                icon: "wind",
                value: model.vitalsDisplay.breathingRPM,
                unit: "brpm",
                color: BrandColor.mint
            )
            MetricBadge(
                icon: "waveform.path.ecg",
                value: String(format: "%.0f%%", model.stressScore * 100),
                unit: "stress",
                color: model.stressLevel.color
            )
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: Spacing.md) {
            HStack(spacing: Spacing.md) {
                Button(action: onDismiss) {
                    Text("Finish")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .background(Color.white.opacity(0.15))
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)

                Button(action: { engine.restart() }) {
                    Text("Start over")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .background(BrandColor.teal.opacity(0.3))
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
            }

            // Short, factual, stated once. Lightheadedness during breath
            // work is common enough to be worth naming, and someone who
            // feels it should know that stopping is the correct response
            // rather than something to push through.
            Text("Stop if you feel lightheaded — breathe normally and try a gentler pattern next time.")
                .font(.system(size: 10))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.45))
        }
    }
}

// MARK: - Metric Badge

struct MetricBadge: View {
    let icon: String
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)

            Text(value)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()

            Text(unit)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(10)
        .frame(minWidth: 62)
        .background(Color.white.opacity(0.08))
        .cornerRadius(8)
    }
}
