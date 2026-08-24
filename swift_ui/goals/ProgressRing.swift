import SwiftUI

/// Apple Health–style progress ring.
///
/// Kept as its own file and free of goal-specific types so it can be
/// reused anywhere a 0...1 value needs rendering — it takes a fraction
/// and a colour, nothing more.
struct ProgressRing: View {
    let fraction: Double
    let color: Color

    var lineWidth: CGFloat = 10
    var showsGlowWhenComplete: Bool = true

    private var clamped: Double { min(max(fraction, 0), 1) }
    private var isComplete: Bool { clamped >= 1.0 }

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.15), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: clamped)
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(
                    color: isComplete && showsGlowWhenComplete ? color.opacity(0.6) : .clear,
                    radius: 6
                )
        }
        .animation(.easeOut(duration: 0.6), value: clamped)
    }
}

/// Ring with a label stacked inside it.
struct LabeledProgressRing: View {
    let fraction: Double
    let color: Color
    let icon: String
    var size: CGFloat = 76

    private var percentText: String {
        "\(Int((min(max(fraction, 0), 1) * 100).rounded()))%"
    }

    var body: some View {
        ZStack {
            ProgressRing(fraction: fraction, color: color, lineWidth: size * 0.13)

            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: size * 0.22, weight: .semibold))
                    .foregroundStyle(color)

                Text(percentText)
                    .font(.system(size: size * 0.16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .monospacedDigit()
            }
        }
        .frame(width: size, height: size)
    }
}

#if DEBUG
#Preview {
    HStack(spacing: 24) {
        LabeledProgressRing(fraction: 0.35, color: BrandColor.teal, icon: "record.circle")
        LabeledProgressRing(fraction: 0.72, color: BrandColor.mint, icon: "wind")
        LabeledProgressRing(fraction: 1.0, color: BrandColor.amber, icon: "leaf.fill")
    }
    .padding(32)
    .background(BrandColor.slate)
}
#endif
