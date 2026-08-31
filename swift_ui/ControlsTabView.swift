import SwiftUI

/// Settings and controls panel — API key input, start/stop, error display,
/// and session statistics.
struct ControlsTabView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Composure")
                        .font(.title.weight(.bold))
                    Text("Bio-Adaptive Workspace")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                // API Key Input
                VStack(alignment: .leading, spacing: 8) {
                    Text("SmartSpectra API Key")
                        .font(.headline)
                    SecureField("Paste your API key here", text: $model.apiKeyInput)
                        .textFieldStyle(.roundedBorder)
                    Text("Stored securely in Keychain, never transmitted unnecessarily.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }

                // Stress Status Card
                VStack(alignment: .leading, spacing: 8) {
                    Text("Current Status")
                        .font(.headline)

                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Stress Level")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.7))
                            Text(model.stressLevel.label)
                                .font(.callout.weight(.bold))
                                .foregroundStyle(model.stressLevel.color)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Score")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.7))
                            Text(String(format: "%.0f%%", model.stressScore * 100))
                                .font(.callout.weight(.bold))
                                .foregroundStyle(model.stressLevel.color)
                        }
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.04))
                    .cornerRadius(8)
                }

                // Session Controls
                HStack(spacing: 12) {
                    Button(action: { model.start() }) {
                        Label("Start", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(BrandColor.teal)
                    .disabled(model.isRunning)

                    Button(action: { model.stop() }) {
                        Label("Stop", systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!model.isRunning)
                }

                BaselineCalibrationCard()

                // Error Display
                if !model.errorMessage.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(.red)
                            Text("Error")
                                .font(.caption.weight(.semibold))
                        }
                        Text(model.errorMessage)
                            .font(.caption)
                            .lineLimit(3)
                    }
                    .padding(8)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(6)
                }

                // Session Stats (only when running)
                if model.isRunning {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Session Stats")
                            .font(.headline)

                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Duration")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.7))
                                Text(DurationFormatter.mmss(model.sessionStats.elapsedSeconds))
                                    .font(.caption.weight(.bold))
                                    .monospacedDigit()
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("Peak Stress")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.7))
                                Text(String(format: "%.0f%%", model.sessionStats.peakStress * 100))
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(BrandColor.coral)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("Avg Stress")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.7))
                                Text(String(format: "%.0f%%", model.sessionStats.averageStress * 100))
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(BrandColor.teal)
                            }
                        }
                        .padding(8)
                        .background(Color.white.opacity(0.04))
                        .cornerRadius(6)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(20)
        }
    }
}
