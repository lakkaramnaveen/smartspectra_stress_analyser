import SwiftUI

/// Game control panel — difficulty selection, session stats, eye tracking
/// status, and the "Launch Game" button.
struct GameTabView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var showGameFullscreen: Bool

    var body: some View {
        VStack(spacing: 16) {
            // Difficulty selector
            VStack(alignment: .leading, spacing: 8) {
                Text("Difficulty")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)

                HStack(spacing: 8) {
                    ForEach(GameDifficulty.allCases, id: \.self) { difficulty in
                        let isSelected = model.gameDifficulty == difficulty
                        Button(action: { model.gameDifficulty = difficulty }) {
                            Text(difficulty.label)
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(8)
                                .background(
                                    isSelected ? BrandColor.teal : Color.white.opacity(0.1)
                                )
                                .cornerRadius(6)
                        }
                        .foregroundStyle(.white)
                    }
                }
            }

            // Game statistics
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Session Stats")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white)

                        Text("Balloon Hunt")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    Spacer()
                }

                Divider()
                    .opacity(0.1)

                VStack(spacing: 12) {
                    StatsRow(
                        icon: "balloon.fill",
                        label: "Balloons Popped",
                        value: "\(model.gameStats.balloonsPopped)",
                        color: BrandColor.coral
                    )
                    StatsRow(
                        icon: "star.fill",
                        label: "Score",
                        value: "\(model.gameStats.score)",
                        color: BrandColor.mint
                    )
                    StatsRow(
                        icon: "timer",
                        label: "Time",
                        value: DurationFormatter.mmss(model.gameStats.elapsedSeconds),
                        color: BrandColor.teal
                    )
                }
            }
            .padding(12)
            .background(Color.white.opacity(0.04))
            .cornerRadius(8)

            // Eye tracking status
            VStack(spacing: 8) {
                HStack {
                    Image(
                        systemName: model.isEyeTrackingAvailable ? "eye" : "eye.slash"
                    )
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(
                        model.isEyeTrackingAvailable ? BrandColor.mint : BrandColor.coral
                    )

                    Text("Eye Tracking")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white)

                    Spacer()

                    if model.isEyeTrackingAvailable {
                        Text("\(Int(model.gaze.confidence * 100))%")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(BrandColor.mint)
                    } else {
                        Text("Offline")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(BrandColor.coral)
                    }
                }
                .padding(8)
                .background(Color.white.opacity(0.05))
                .cornerRadius(6)

                HStack {
                    Image(systemName: "eyes")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(BrandColor.teal)

                    Text("Blink Detection")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white)

                    Spacer()

                    Text(model.blinkDetected ? "●" : "○")
                        .font(.title3)
                        .foregroundStyle(
                            model.blinkDetected ? BrandColor.teal : .white.opacity(0.3)
                        )
                }
                .padding(8)
                .background(Color.white.opacity(0.05))
                .cornerRadius(6)
            }

            Divider()
                .opacity(0.1)

            // Launch button
            Button(action: { showGameFullscreen = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "gamecontroller.fill")
                    Text("Launch Balloon Hunt")
                }
                .frame(maxWidth: .infinity)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    BrandColor.mint.opacity(0.8),
                                    BrandColor.teal.opacity(0.8)
                                ]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
                .foregroundStyle(.white)
                .font(.system(size: 16, weight: .semibold))
            }
            .disabled(!model.isRunning)

            // Instructions
            VStack(alignment: .leading, spacing: 8) {
                Text("How to Play")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "eye")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(BrandColor.teal)
                            .frame(width: 20)

                        Text("Look at balloons floating up")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "eyes")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(BrandColor.coral)
                            .frame(width: 20)

                        Text("Blink to shoot and pop them")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(BrandColor.mint)
                            .frame(width: 20)

                        Text("Earn points (more in higher difficulty)")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .padding(.top, 4)
            }
            .padding(12)
            .background(Color.white.opacity(0.04))
            .cornerRadius(8)

            Spacer(minLength: 0)
        }
        .padding(20)
    }
}
