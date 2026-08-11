import SwiftUI

/// Guided breathing intervention shown only when stress reaches critical
/// levels (95%+ score). Coaches the user through 6 breathing cycles
/// (4s in, 6s out each) and displays live metrics.
///
/// Design rationale:
/// - Only appears at extreme stress threshold (tuned higher than earlier
///   versions after user feedback).
/// - Auto-dismisses after 60 seconds or 6 cycles, or user can skip.
/// - Shows heart rate and breathing rate changing in real time.
/// - Emotional state display helps the user track improvement.
struct BreathingPacerView: View {
    @Binding var isActive: Bool
    @EnvironmentObject private var model: AppModel

    @State private var scale: CGFloat = 0.5
    @State private var opacity: Double = 0.3
    @State private var instruction: String = "Get Ready..."
    @State private var animationTask: Task<Void, Never>?
    @State private var cycleCount: Int = 0
    @State private var breathCycleProgress: Double = 0.0

    var body: some View {
        ZStack {
            // Semi-transparent dark background
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
                .opacity(0.92)

            VStack(spacing: 32) {
                // Critical stress alert header
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(BrandColor.coral)

                        VStack(alignment: .leading, spacing: 0) {
                            Text("Critical Stress Alert")
                                .font(.title2.weight(.bold))
                                .foregroundStyle(.white)

                            Text("Extreme stress detected — immediate intervention needed")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }

                    // Current stress and emotion display
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Stress Level")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.7))

                            Text(String(format: "%.0f%%", model.stressScore * 100))
                                .font(.title2.weight(.bold))
                                .foregroundStyle(BrandColor.coral)
                        }

                        Spacer()

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Emotional State")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.7))

                            Text(model.emotionalState.label)
                                .font(.title3.weight(.bold))
                                .foregroundStyle(model.emotionalState.color)
                        }
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.04))
                    .cornerRadius(8)
                }

                // Breathing orb animation
                ZStack {
                    Circle()
                        .fill(BrandColor.teal.opacity(0.3))
                        .frame(width: 280, height: 280)
                        .blur(radius: 30)
                        .scaleEffect(scale * 0.95)

                    Circle()
                        .fill(BrandColor.mint.opacity(0.5))
                        .frame(width: 200, height: 200)
                        .blur(radius: 15)
                        .scaleEffect(scale)

                    Circle()
                        .fill(BrandColor.mint.opacity(0.2))
                        .frame(width: 160, height: 160)

                    Circle()
                        .stroke(BrandColor.teal.opacity(0.6), lineWidth: 2)
                        .frame(width: 160, height: 160)

                    VStack(spacing: 16) {
                        Text(instruction)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                            .transition(.opacity)

                        // Live metrics during breathing
                        HStack(spacing: 12) {
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
                        }
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                }
                .opacity(opacity)
                .frame(height: 320)

                // Breathing cycle progress bar
                VStack(spacing: 8) {
                    HStack {
                        Text("Breath Cycle")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                        Spacer()
                        Text("\(Int(breathCycleProgress * 100))%")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(BrandColor.teal)
                    }

                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.1))

                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [BrandColor.mint, BrandColor.teal]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(0, 280 * breathCycleProgress))
                    }
                    .frame(height: 6)
                    .frame(maxWidth: 280)
                }
                .padding(.horizontal, 20)

                // Stress reduction indicator
                VStack(spacing: 6) {
                    HStack {
                        Text("Stress Reduction")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                        Spacer()
                        Text(String(format: "%.1f%%", model.stressScore * 100))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(model.emotionalState.color)
                    }

                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.1))

                        RoundedRectangle(cornerRadius: 4)
                            .fill(model.emotionalState.color)
                            .frame(width: max(0, 280 * model.stressScore))
                    }
                    .frame(height: 6)
                    .frame(maxWidth: 280)

                    HStack(spacing: 8) {
                        Circle()
                            .fill(model.emotionalState.color)
                            .frame(width: 8, height: 8)

                        Text(model.emotionalState.label)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))

                        Spacer()
                    }
                }
                .padding(.horizontal, 20)

                // Cycle counter
                HStack {
                    Text("Breathing Cycles")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))

                    Spacer()

                    Text("\(cycleCount) / 6")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(BrandColor.teal)
                }
                .padding(.horizontal, 20)

                Spacer()

                // Action buttons
                HStack(spacing: 12) {
                    Button(action: { stopBreathing() }) {
                        Text("Exit")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(12)
                            .background(Color.white.opacity(0.15))
                            .cornerRadius(8)
                    }
                    .tint(.white)

                    Button(action: { resetCycles() }) {
                        Text("Reset Cycles")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(12)
                            .background(BrandColor.teal.opacity(0.3))
                            .cornerRadius(8)
                    }
                    .tint(BrandColor.teal)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .onAppear {
            startBreathing()
        }
        .onDisappear {
            animationTask?.cancel()
        }
    }

    // MARK: - Animation Loop

    private func startBreathing() {
        cycleCount = 0
        performBreathCycle()
    }

    private func performBreathCycle() {
        cycleCount += 1

        // Inhale (4 seconds)
        withAnimation(.easeInOut(duration: 4.0)) {
            scale = 1.2
            opacity = 1.0
            instruction = "Breathe In..."
            breathCycleProgress = 0.4
        }

        // Exhale (6 seconds)
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            withAnimation(.easeInOut(duration: 6.0)) {
                scale = 0.5
                opacity = 0.3
                instruction = "Breathe Out..."
                breathCycleProgress = 1.0
            }
        }

        // Reset for next cycle or auto-exit
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
            breathCycleProgress = 0.0

            if cycleCount >= 6 {
                model.goals.recordBreathingCompleted()  
                stopBreathing()
            } else {
                performBreathCycle()
            }
        }
    }

    private func resetCycles() {
        animationTask?.cancel()
        cycleCount = 0
        breathCycleProgress = 0.0
        startBreathing()
    }

    private func stopBreathing() {
        animationTask?.cancel()
        withAnimation(.easeOut(duration: 0.5)) {
            isActive = false
        }
    }
}

// MARK: - Supporting Components

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
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text(unit)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(8)
        .frame(minWidth: 50)
        .background(Color.white.opacity(0.08))
        .cornerRadius(8)
    }
}
