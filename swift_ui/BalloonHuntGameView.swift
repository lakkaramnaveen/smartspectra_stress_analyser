import SwiftUI

/// Fullscreen eye-tracking game with EXIT BUTTON and NAVIGATION (FIXED - no broken shortcuts)
struct BalloonHuntGameView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) var dismiss
    @State private var balloons: [Balloon] = []
    @State private var gameLoopTask: Task<Void, Never>?
    @State private var spawnTask: Task<Void, Never>?
    @State private var showGameComplete = false
    @State private var showExitConfirm = false

    private let gameAreaWidth: CGFloat = 600
    private let gameAreaHeight: CGFloat = 800

    var gameAreaMinX: CGFloat {
        (1040 - 320 - gameAreaWidth) / 2
    }

    var gameAreaMinY: CGFloat { 20 }

    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.08, green: 0.12, blue: 0.16),
                    Color(red: 0.12, green: 0.15, blue: 0.20)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header with EXIT BUTTON
                HStack(spacing: 16) {
                    // EXIT BUTTON (red, top-left)
                    Button(action: { showExitConfirm = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle.fill")
                            Text("Exit")
                        }
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(6)
                    }
                    .foregroundStyle(BrandColor.coral)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Balloon Hunt")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)

                        Text("Difficulty: \(model.gameDifficulty.label)")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                    }

                    Spacer()

                    HStack(spacing: 16) {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Score")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.7))
                            Text("\(model.gameStats.score)")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(BrandColor.teal)
                        }

                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Time")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.7))
                            Text(DurationFormatter.mmss(model.gameStats.elapsedSeconds))
                                .font(.title3.weight(.bold))
                                .foregroundStyle(BrandColor.mint)
                        }

                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Popped")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.7))
                            Text("\(model.gameStats.balloonsPopped)")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(BrandColor.coral)
                        }
                    }
                }
                .padding(16)
                .background(Color.white.opacity(0.04))

                // Game canvas
                ZStack {
                    EyeTrackingCrosshair(model: model, gameAreaWidth: gameAreaWidth, gameAreaHeight: gameAreaHeight)

                    ForEach(balloons) { balloon in
                        Circle()
                            .fill(balloon.color)
                            .frame(width: balloon.diameter, height: balloon.diameter)
                            .overlay(
                                Circle()
                                    .stroke(balloon.color.opacity(0.5), lineWidth: 1.5)
                            )
                            .overlay(
                                Circle()
                                    .fill(Color.white.opacity(0.3))
                                    .frame(width: balloon.diameter * 0.35)
                                    .offset(
                                        x: -balloon.diameter * 0.15,
                                        y: -balloon.diameter * 0.15
                                    )
                            )
                            .position(
                                x: gameAreaMinX + balloon.position.x,
                                y: gameAreaMinY + balloon.position.y
                            )
                    }

                    if showGameComplete {
                        VStack(spacing: 16) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(BrandColor.amber)

                            Text("Perfect!")
                                .font(.title2.weight(.bold))
                                .foregroundStyle(.white)

                            Text("\(model.gameStats.balloonsPopped) balloons in \(DurationFormatter.mmss(model.gameStats.elapsedSeconds))")
                                .font(.body)
                                .foregroundStyle(.white.opacity(0.8))

                            Text("Final Score: \(model.gameStats.score)")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(BrandColor.teal)
                        }
                        .padding(24)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(16)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: gameAreaHeight)
                .background(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color(red: 0.15, green: 0.20, blue: 0.25),
                            Color(red: 0.08, green: 0.12, blue: 0.16)
                        ]),
                        center: .center,
                        startRadius: 10,
                        endRadius: 300
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .padding(12)

                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        HStack(spacing: 4) {
                            Image(systemName: "eye")
                                .font(.system(size: 10, weight: .semibold))
                            Text("Look at balloons")
                                .font(.caption)
                        }

                        Spacer()

                        HStack(spacing: 4) {
                            Image(systemName: "eyes")
                                .font(.system(size: 10, weight: .semibold))
                            Text("Blink to shoot")
                                .font(.caption)
                        }
                    }

                    HStack(spacing: 8) {
                        Circle()
                            .fill(
                                model.gaze.confidence > 0.7 ? BrandColor.mint : BrandColor.amber
                            )
                            .frame(width: 6, height: 6)

                        Text("Eye Tracking: \(Int(model.gaze.confidence * 100))%")
                            .font(.caption)

                        Spacer()

                        Text(model.blinkDetected ? "Blink! 👁️" : "Ready")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(model.blinkDetected ? BrandColor.amber : .white.opacity(0.6))
                    }
                }
                .foregroundStyle(.white.opacity(0.6))
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
        .onAppear {
            startGame()
        }
        .onDisappear {
            stopGame()
        }
        .onChange(of: model.blinkDetected) {
            if model.blinkDetected {
                handleBlink()
            }
        }
        // EXIT CONFIRMATION DIALOG
        .alert("Exit Game?", isPresented: $showExitConfirm) {
            Button("Continue Game", role: .cancel) { }
            Button("Exit", role: .destructive) {
                stopGame()
                dismiss()
            }
        } message: {
            Text("Your progress will not be saved.")
        }
    }

    private func startGame() {
        model.startGame(difficulty: model.gameDifficulty)
        balloons = []
        showGameComplete = false

        spawnBalloon()

        spawnTask?.cancel()
        spawnTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(800))
                guard !Task.isCancelled else { return }
                spawnBalloon()
            }
        }

        gameLoopTask?.cancel()
        gameLoopTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                guard !Task.isCancelled else { return }
                updateGame()
            }
        }
    }

    private func stopGame() {
        model.stopGame()
        gameLoopTask?.cancel()
        spawnTask?.cancel()
    }

    private func spawnBalloon() {
        guard balloons.count < 20 else { return }

        let velocityRange = model.gameDifficulty.balloonVelocityRange
        let newBalloon = Balloon(
            id: UUID(),
            position: CGPoint(
                x: CGFloat.random(in: 30...(gameAreaWidth - 30)),
                y: gameAreaHeight + 20
            ),
            diameter: CGFloat.random(in: 25...55),
            color: randomBalloonColor(),
            velocity: CGFloat.random(in: velocityRange)
        )
        balloons.append(newBalloon)
    }

    private func updateGame() {
        balloons = balloons.map { balloon in
            var updated = balloon
            updated.position.y -= updated.velocity * 0.016
            return updated
        }

        balloons.removeAll { $0.position.y < -100 }

        if balloons.isEmpty, model.gameStats.elapsedSeconds > 3.0 {
            showGameComplete = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                stopGame()
                dismiss()
            }
        }
    }

    private func handleBlink() {
        let crosshairX = gameAreaMinX + (model.gaze.x * gameAreaWidth)
        let crosshairY = gameAreaMinY + (model.gaze.y * gameAreaHeight)

        for (index, balloon) in balloons.enumerated() {
            let balloonCenterX = gameAreaMinX + balloon.position.x
            let balloonCenterY = gameAreaMinY + balloon.position.y

            let dx = crosshairX - balloonCenterX
            let dy = crosshairY - balloonCenterY
            let distance = sqrt(dx * dx + dy * dy)

            if distance < (balloon.diameter / 2.0) {
                balloons.remove(at: index)
                model.recordBalloonPop()
                triggerHapticFeedback()
                break
            }
        }
    }

    private func triggerHapticFeedback() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    private func randomBalloonColor() -> Color {
        let colors: [Color] = [
            BrandColor.coral, BrandColor.teal, BrandColor.mint,
            BrandColor.amber, Color(red: 0.60, green: 0.60, blue: 1.0)
        ]
        return colors.randomElement() ?? colors[0]
    }
}

// MARK: - Eye Tracking Crosshair

struct EyeTrackingCrosshair: View {
    let model: AppModel
    let gameAreaWidth: CGFloat
    let gameAreaHeight: CGFloat

    var crosshairColor: Color {
        if model.gaze.confidence > 0.8 {
            return BrandColor.mint
        } else if model.gaze.confidence > 0.5 {
            return BrandColor.amber
        } else {
            return BrandColor.coral
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(crosshairColor.opacity(0.3), lineWidth: 1.5)
                .frame(width: 60, height: 60)

            Circle()
                .stroke(crosshairColor.opacity(0.5), lineWidth: 1)
                .frame(width: 40, height: 40)

            Circle()
                .stroke(crosshairColor.opacity(0.7), lineWidth: 1)
                .frame(width: 20, height: 20)

            Circle()
                .fill(crosshairColor)
                .frame(width: model.blinkDetected ? 14 : 8, height: model.blinkDetected ? 14 : 8)

            if model.blinkDetected {
                Circle()
                    .stroke(crosshairColor, lineWidth: 2)
                    .frame(width: 40, height: 40)
                    .opacity(0.6)
            }

            Circle()
                .stroke(crosshairColor.opacity(0.2), lineWidth: 2)
                .frame(width: 80, height: 80)
        }
        .offset(
            x: model.gaze.x * gameAreaWidth - gameAreaWidth / 2,
            y: model.gaze.y * gameAreaHeight - gameAreaHeight / 2
        )
    }
}
