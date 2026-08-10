import SwiftUI

/// Displays detected emotional state based on vital signs, along with
/// intensity meter, contributing factors, and personalized analysis.
struct EmotionalDetectorView: View {
    @EnvironmentObject private var model: AppModel

    private let emotions: [(name: String, icon: String, state: EmotionalState)] = [
        ("Calm", "leaf", .calm),
        ("Focused", "target", .focused),
        ("Anxious", "exclamationmark.circle", .anxious),
        ("Stressed", "flame", .stressed)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("Emotional State")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)

                Text("Real-time analysis from vitals")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }

            // Main emotion display
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(model.emotionalState.color.opacity(0.15))
                        .frame(width: 160, height: 160)

                    Circle()
                        .stroke(model.emotionalState.color.opacity(0.3), lineWidth: 2)
                        .frame(width: 160, height: 160)

                    VStack(spacing: 8) {
                        Image(systemName: model.emotionalState.icon)
                            .font(.system(size: 48, weight: .semibold))
                            .foregroundStyle(model.emotionalState.color)

                        Text(model.emotionalState.label)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)

                // Intensity bar
                VStack(spacing: 6) {
                    HStack {
                        Text("Intensity")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.8))
                        Spacer()
                        Text(String(format: "%.0f%%", model.emotionIntensity * 100))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(model.emotionalState.color)
                    }

                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.white.opacity(0.1))

                        RoundedRectangle(cornerRadius: 3)
                            .fill(model.emotionalState.color)
                            .frame(width: max(0, 220 * model.emotionIntensity))
                    }
                    .frame(height: 6)
                    .frame(maxWidth: 220)
                }
                .padding(.horizontal, 16)

                // Vital signs contributing to this state
                HStack(spacing: 12) {
                    VitalIndicator(
                        icon: "heart.fill",
                        label: "Heart",
                        value: model.vitalsDisplay.pulseBPM,
                        unit: "bpm"
                    )

                    VitalIndicator(
                        icon: "wind",
                        label: "Breath",
                        value: model.vitalsDisplay.breathingRPM,
                        unit: "rpm"
                    )

                    VitalIndicator(
                        icon: "waveform.path.ecg",
                        label: "EDA",
                        value: model.vitalsDisplay.edaLevel,
                        unit: ""
                    )
                }
                .padding(.horizontal, 12)
            }
            .padding(.horizontal, 12)
            .background(Color.white.opacity(0.04))
            .cornerRadius(12)

            // Emotion spectrum
            VStack(spacing: 10) {
                Text("Emotional Spectrum")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)

                HStack(spacing: 8) {
                    ForEach(emotions, id: \.name) { emotion in
                        EmotionCard(
                            icon: emotion.icon,
                            label: emotion.name,
                            isActive: model.emotionalState == emotion.state,
                            color: emotion.state.color
                        )
                    }
                }
            }
            .padding(.horizontal, 12)

            // Analysis text
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "brain")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(model.emotionalState.color)

                    Text("Analysis")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                }

                Text(emotionalAnalysis)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(4)
            }
            .padding(12)
            .background(Color.white.opacity(0.06))
            .cornerRadius(8)
            .padding(.horizontal, 12)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 4)
        .background(Color.white.opacity(0.03))
        .cornerRadius(12)
    }

    private var emotionalAnalysis: String {
        let emotion = model.emotionalState
        let intensity = model.emotionIntensity

        switch emotion {
        case .calm:
            if intensity < 0.3 {
                return "Excellent baseline composure. You're well-rested and centered. Maintain this state."
            } else {
                return "Good emotional balance. You're managing stress effectively with stable vitals."
            }

        case .focused:
            if intensity < 0.5 {
                return "Healthy engagement detected. Your attention is sharp and your body is responsive."
            } else {
                return "Deep focus mode active. Channel this energy into your current task."
            }

        case .anxious:
            if intensity < 0.65 {
                return "Mild stress present. Consider a brief pause or use the breathing pacer to reset."
            } else {
                return "Noticeable anxiety. Take a moment for guided breathing to help regulate your system."
            }

        case .stressed:
            return "High stress alert. Your body is in fight-or-flight mode. Use the breathing pacer now."
        }
    }
}

// MARK: - Supporting Components

struct VitalIndicator: View {
    let icon: String
    let label: String
    let value: String
    let unit: String

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))

                Text(label)
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(0.7))

            HStack(spacing: 2) {
                Text(value)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(Color.white.opacity(0.08))
        .cornerRadius(6)
    }
}

struct EmotionCard: View {
    let icon: String
    let label: String
    let isActive: Bool
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color)

            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(isActive ? .white : .white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(isActive ? color.opacity(0.2) : Color.white.opacity(0.05))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isActive ? color.opacity(0.6) : Color.clear, lineWidth: 1.5)
        )
    }
}
