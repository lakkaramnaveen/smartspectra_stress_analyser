import SwiftUI

/// Controls-tab card for personal baseline calibration: shows current
/// calibration status and lets the user run/cancel/reset it.
///
/// Requires a live session (camera + SDK already running via "Start")
/// since calibration needs real vitals to average — see
/// `AppModel.startCalibration()`.
struct BaselineCalibrationCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Personal Baseline")
                .font(.headline)

            if model.isCalibrating {
                calibratingContent
            } else {
                idleContent
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.04))
        .cornerRadius(8)
    }

    private var calibratingContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sit still and breathe normally…")
                .font(.callout.weight(.medium))

            ProgressView(value: model.calibrationProgress)
                .tint(BrandColor.teal)

            HStack {
                Text("\(Int(model.calibrationProgress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Button("Cancel", action: { model.cancelCalibration() })
                    .buttonStyle(.borderless)
                    .font(.caption.weight(.semibold))
            }
        }
    }

    private var idleContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let baseline = model.baseline {
                Text("Calibrated \(baseline.calibratedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                Text("Personalized scoring active — thresholds are tuned to your own resting vitals.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            } else {
                Text("Using default thresholds, same for every user. Calibrate to personalize scoring to your own resting vitals.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }

            HStack(spacing: 12) {
                Button(action: { model.startCalibration() }) {
                    Label(
                        model.baseline == nil ? "Calibrate Baseline (60s)" : "Recalibrate (60s)",
                        systemImage: "figure.mind.and.body"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!model.isRunning)

                if model.baseline != nil {
                    Button("Reset", role: .destructive, action: { model.resetBaseline() })
                        .buttonStyle(.borderless)
                }
            }

            if !model.isRunning {
                Text("Click Start first — calibration needs a live session.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
    }
}
