import SwiftUI

/// First-run welcome screen, shown once between unlocking the app and
/// reaching `ContentView`.
///
/// Before this, a brand-new user's very first screen after Touch ID was a
/// bare "SmartSpectra API Key" text field with a placeholder and nothing
/// else — no explanation of what the app measures, what the key is for,
/// or what happens to the data it collects. This fills that gap without
/// turning it into a multi-step wizard: one screen, three facts, one
/// button.
///
/// Every claim on this screen is something already verified true
/// elsewhere in this codebase this session — it doesn't say anything
/// about the camera feed or the SmartSpectra SDK's own network behavior,
/// since that's outside what this app's code can vouch for.
struct OnboardingView: View {
    let onContinue: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [BrandColor.slate, Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [BrandColor.teal, BrandColor.mint],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 72, height: 72)

                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(.white)
                    }

                    Text("Welcome to SmartSpectra")
                        .font(.title.weight(.bold))
                        .foregroundStyle(.white)

                    Text("Camera-based vitals and stress monitoring — no wearables needed.")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.65))
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 18) {
                    OnboardingFact(
                        icon: "heart.text.square",
                        title: "What it measures",
                        detail: "Pulse, breathing rate, and electrodermal activity from your camera feed, used to estimate a live stress score and emotional state."
                    )

                    OnboardingFact(
                        icon: "key.fill",
                        title: "A SmartSpectra API key is required",
                        detail: "Paste one on the next screen to start a session. It's stored in the macOS Keychain, never written anywhere in plain text."
                    )

                    OnboardingFact(
                        icon: "lock.shield",
                        title: "Your session history stays on this Mac",
                        detail: "Stress and vitals history from past sessions is saved locally and never uploaded. Delete any session at any time from the History tab."
                    )
                }
                .frame(maxWidth: 460, alignment: .leading)
                .padding(20)
                .background(Color.white.opacity(0.05))
                .cornerRadius(14)

                Button(action: onContinue) {
                    Text("Get Started")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: 220)
                }
                .buttonStyle(.borderedProminent)
                .tint(BrandColor.teal)
                .controlSize(.large)
            }
            .padding(40)
            .frame(maxWidth: 560)
        }
    }
}

private struct OnboardingFact: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(BrandColor.mint)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }
}
