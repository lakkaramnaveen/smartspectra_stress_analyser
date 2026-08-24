import SwiftUI

struct BiofeedbackArtView: View {
    @EnvironmentObject private var model: AppModel
    @State private var toneEngine = AmbientToneEngine()

    @State private var engine: ParticleFieldEngine?
    @State private var lastFrameDate: Date?
    @State private var isSoundEnabled = false
    @State private var volume: Double = 0.5

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            header
            canvasArea
            gradientTimeline
            audioControls
        }
        .padding(Spacing.xl)
        .onDisappear { toneEngine.stop() }
        .onChange(of: model.stressScore) { _, newScore in
            toneEngine.updateStress(newScore)
        }
        .onChange(of: model.vitalsDisplay.breathingRPM) { _, newValue in
            if let rate = Double(newValue) {
                toneEngine.updateBreathingRate(rate)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Biofeedback Art")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
            Text("Your stress, made visible")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    // MARK: - Canvas

    private var canvasArea: some View {
        GeometryReader { proxy in
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    guard let engine else { return }
                    for particle in engine.particles {
                        let rect = CGRect(
                            x: particle.position.x - particle.size / 2,
                            y: particle.position.y - particle.size / 2,
                            width: particle.size,
                            height: particle.size
                        )
                        context.opacity = particle.opacity
                        context.fill(
                            Path(ellipseIn: rect),
                            with: .color(Color(hue: particle.hue, saturation: 0.55, brightness: 0.9))
                        )
                    }
                }
                // Simulation state is advanced here, as a side effect
                // triggered by the timeline tick, rather than mutated
                // directly inside the Canvas draw closure above. Doing
                // it inside the draw closure would mutate `@State`
                // during a render pass, which SwiftUI can flag as
                // undefined behavior. The one-frame lag this introduces
                // — advance, then draw on the *next* tick — is roughly
                // 16ms, and genuinely imperceptible for an animation
                // this deliberately slow and gentle.
                .onChange(of: timeline.date) { _, newDate in
                    advance(to: newDate, in: proxy.size)
                }
            }
            .onAppear {
                if engine == nil {
                    engine = ParticleFieldEngine(bounds: proxy.size)
                }
            }
        }
        .frame(minHeight: 320)
        .background(
            RadialGradient(
                colors: [StressLevel.classify(model.stressScore).color.opacity(0.3), BrandColor.slate],
                center: .center,
                startRadius: 20,
                endRadius: 260
            )
        )
        .clipped()
        .cornerRadius(16)
    }

    private func advance(to date: Date, in size: CGSize) {
        defer { lastFrameDate = date }
        guard let last = lastFrameDate else { return }
        let dt = date.timeIntervalSince(last)
        // Guards against a huge dt after the view was backgrounded or
        // paused — without this, resuming would dump a burst of
        // "missed" particles all at once.
        guard dt > 0, dt < 1 else { return }
        engine?.step(dt: dt, stressScore: model.stressScore)
    }

    // MARK: - Timeline

    private var gradientTimeline: some View {
        Canvas { context, size in
            let history = model.stressHistory
            guard history.count > 1 else { return }

            for index in 0..<(history.count - 1) {
                let x0 = size.width * CGFloat(index) / CGFloat(history.count - 1)
                let x1 = size.width * CGFloat(index + 1) / CGFloat(history.count - 1)

                var path = Path()
                path.move(to: CGPoint(x: x0, y: size.height / 2))
                path.addLine(to: CGPoint(x: x1, y: size.height / 2))

                context.stroke(
                    path,
                    with: .color(StressLevel.classify(history[index]).color),
                    lineWidth: 3
                )
            }
        }
        .frame(height: 24)
    }

    // MARK: - Audio

    private var audioControls: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.md) {
                Button(action: toggleSound) {
                    Image(systemName: isSoundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isSoundEnabled ? BrandColor.teal : .white.opacity(0.4))
                }
                .buttonStyle(.plain)

                if isSoundEnabled {
                    Slider(
                        value: Binding(
                            get: { volume },
                            set: { volume = $0; toneEngine.setVolume($0) }
                        ),
                        in: 0...1
                    )
                    .tint(BrandColor.teal)
                }

                Spacer()

                Text(StressLevel.classify(model.stressScore).label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(StressLevel.classify(model.stressScore).color)
            }

            Text("Sound is off by default. When on, it's a single soft tone whose pitch drifts gently with your stress reading, and whose loudness rises and falls with your actual breathing rate rather than an arbitrary rhythm.")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func toggleSound() {
        isSoundEnabled.toggle()
        if isSoundEnabled {
            try? toneEngine.start()
            toneEngine.setVolume(volume)
        } else {
            toneEngine.stop()
        }
    }
}

#if DEBUG
#Preview {
    BiofeedbackArtView()
        .environmentObject(AppModel())
        .frame(width: 460, height: 620)
        .background(BrandColor.slate)
}
#endif
