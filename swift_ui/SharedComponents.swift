import SwiftUI

// MARK: - Premium Vital Tile (Bigger Heart Rate Font)

struct VitalTile: View {
    let title: String
    let value: String
    let unit: String
    let confidence: String
    let icon: String
    let color: Color
    let points: [Double]

    var body: some View {
        VStack(spacing: Spacing.md) {
            // Header with icon
            HStack(spacing: Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(color)

                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .tracking(0.3)

                Spacer()

                if !confidence.isEmpty {
                    Text(confidence)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            // Main value (BIG FONT - 36-40pt) ← PREMIUM
            HStack(spacing: Spacing.sm) {
                Text(value)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .tracking(-0.5)
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(unit)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.top, Spacing.sm)
            }

            // Sparkline chart
            if !points.isEmpty {
                Sparkline(data: points, color: color)
                    .frame(height: 32)
            }
        }
        .padding(Spacing.lg)
        .background(
            // Glass morphism effect
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.white.opacity(0.08),
                    Color.white.opacity(0.03)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.white.opacity(0.12),
                            Color.white.opacity(0.04)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Premium Stats Card

struct StatsCard: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(color)

                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .tracking(0.2)

                Spacer()
            }

            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(color)
        }
        .padding(Spacing.md)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.white.opacity(0.06),
                    Color.white.opacity(0.02)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .cornerRadius(10)
    }
}

// MARK: - Premium Stats Row

struct StatsRow: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)

                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
            }

            Spacer()

            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .tracking(-0.3)
        }
        .padding(Spacing.md)
        .background(Color.white.opacity(0.04))
        .cornerRadius(8)
    }
}

// MARK: - Sparkline Chart (For Trend Visualization)

struct Sparkline: View {
    let data: [Double]
    let color: Color

    var body: some View {
        Canvas { context, size in
            guard data.count > 1 else { return }

            var path = Path()
            let width = size.width
            let height = size.height

            for (index, value) in data.enumerated() {
                let x = (width / CGFloat(data.count - 1)) * CGFloat(index)
                let y = height * (1.0 - CGFloat(value))

                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }

            // Fill area under curve
            var fillPath = path
            fillPath.addLine(to: CGPoint(x: width, y: height))
            fillPath.addLine(to: CGPoint(x: 0, y: height))
            fillPath.closeSubpath()

            context.fill(fillPath, with: .color(color.opacity(0.15)))

            // Stroke line
            context.stroke(path, with: .color(color), lineWidth: 2.5)

            // End point indicator
            if let lastValue = data.last {
                let x = width - 4
                let y = height * (1.0 - CGFloat(lastValue)) - 4
                let circlePoint = Path(ellipseIn: CGRect(x: x - 4, y: y - 4, width: 8, height: 8))
                context.fill(circlePoint, with: .color(color))
            }
        }
    }
}

// MARK: - Sparkline Path Helper

struct SparklinePath: Shape {
    let points: [Double]

    func path(in rect: CGRect) -> Path {
        guard points.count > 1 else { return Path() }

        var path = Path()
        let width = rect.width
        let height = rect.height

        for (index, value) in points.enumerated() {
            let x = (width / CGFloat(points.count - 1)) * CGFloat(index)
            let y = height * (1.0 - CGFloat(value))

            if index == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }

        return path
    }
}

// MARK: - Premium Duration Formatter

enum DurationFormatter {
    static func mmss(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
}

// MARK: - Premium Button Style

struct PremiumButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .padding(Spacing.lg)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [
                        color,
                        color.opacity(0.9)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(11)
            .shadow(color: color.opacity(0.4), radius: 8, x: 0, y: 4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
    }
}

// MARK: - Glass Morphism Card Background

struct GlassBackground: View {
    let opacity: CGFloat = 0.06
    let blurRadius: CGFloat = 10

    var body: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                Color.white.opacity(opacity),
                Color.white.opacity(opacity * 0.3)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .blur(radius: blurRadius)
    }
}

// MARK: - Premium Section Header

struct SectionHeader: View {
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)

            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Gradient Text (Premium Effect)

struct GradientText: View {
    let text: String
    let colors: [Color]
    let font: Font

    var body: some View {
        Text(text)
            .font(font)
            .overlay(
                LinearGradient(
                    gradient: Gradient(colors: colors),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .mask(Text(text).font(font))
            )
    }
}

// MARK: - Shake Feedback

/// Horizontal shake for negative feedback — e.g. `AppLockView` on an
/// incorrect passcode. `animatableData` is what SwiftUI actually
/// interpolates: wrap a change to the `trigger` value passed into
/// `.shake(trigger:)` in `withAnimation`, and the intermediate values
/// this receives during that animation produce the oscillation.
private struct ShakeEffect: GeometryEffect {
    var amount: CGFloat = 8
    var shakesPerUnit = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(
            translationX: amount * sin(animatableData * .pi * CGFloat(shakesPerUnit)),
            y: 0
        ))
    }
}

extension View {
    /// Shakes horizontally whenever `trigger` changes. Callers animate the
    /// change themselves — e.g. `withAnimation(.default) { shakeCount += 1 }`
    /// — rather than this modifier owning the animation, so a caller that
    /// wants a different curve or duration isn't fighting a baked-in one.
    func shake(trigger: CGFloat) -> some View {
        modifier(ShakeEffect(animatableData: trigger))
    }
}
