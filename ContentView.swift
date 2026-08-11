import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showGameFullscreen = false
    @State private var activeSidebarTab: SidebarTab = .controls

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                // Main workspace (responsive 60%)
                mainWorkspace
                    .frame(maxWidth: .infinity)

                Divider()

                // Sidebar (responsive 40%, max 500, min 300)
                sidebarPanel
                    .frame(maxWidth: 500)
                    .frame(minWidth: 300)
            }
            
            if let alert = model.prediction.activeAlert {
                VStack {
                    StressAlertBanner(
                        alert: alert,
                        onDismiss: { model.prediction.dismissAlert() },
                        onStartBreathing: { model.beginBreathingManually() }
                    )
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .frame(maxWidth: 520)

                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(500)
            }

            // Game fullscreen overlay
            if showGameFullscreen {
                BalloonHuntGameView()
                    .environmentObject(model)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    .zIndex(1000)
            }
        }
        .animation(.easeInOut, value: showGameFullscreen)
        .animation(.spring(response: 0.4), value: model.prediction.activeAlert)
    }

    // MARK: - Main Workspace

    private var mainWorkspace: some View {
        ZStack {
            Color.black

            if let frame = model.frame {
                Image(nsImage: frame)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "video.slash")
                        .font(.system(size: 44))
                    Text("Camera offline")
                        .font(.title3)
                }
                .foregroundStyle(.secondary)
            }

            VStack {
                HStack {
                    validationPill
                    Spacer()
                    StressTrendPill(forecast: model.prediction.forecast) 
                }
                .padding(18)

                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var validationPill: some View {
        Text(model.validationStatus.isEmpty ? "Waiting..." : model.validationStatus)
            .font(.callout.weight(.medium))
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Sidebar Panel

    private var sidebarPanel: some View {
        VStack(spacing: 0) {
            // Tab buttons
            HStack(spacing: 4) {
                ForEach(SidebarTab.allCases, id: \.self) { tab in
                    Button(action: { activeSidebarTab = tab }) {
                        VStack(spacing: 4) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 16, weight: .semibold))
                            Text(tab.label)
                                .font(.system(size: 8, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(activeSidebarTab == tab ? BrandColor.primaryBlue : .white.opacity(0.5))
                        .padding(.vertical, 8)
                    }
                    .background(
                        activeSidebarTab == tab ? Color.white.opacity(0.1) : Color.clear
                    )
                    .cornerRadius(8)
                }
            }
            .padding(8)
            .background(Color.white.opacity(0.04))

            Divider()

            // Tab content — pulled into its own @ViewBuilder property
            // rather than inlined here, so the switch's result isn't
            // chained directly to a trailing modifier inside the ZStack
            // (harmless, but easy to misread/mis-indent, as happened
            // in the previous version of this file).
            sidebarContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(BrandColor.slate)
    }

    @ViewBuilder
    private var sidebarContent: some View {
        switch activeSidebarTab {
        case .controls:
            ControlsTabView()
                .environmentObject(model)
        case .stress:
            ScrollView {
                StressVisualizationView()
                    .environmentObject(model)
                    .padding(12)
            }
        case .emotions:
            ScrollView {
                EmotionalDetectorView()
                    .environmentObject(model)
                    .padding(12)
            }
        case .game:
            GameTabView(showGameFullscreen: $showGameFullscreen)
                .environmentObject(model)
        case .history:
            SessionHistoryView()
        case .insights:
            InsightsDashboardView()
        case .goals:
            GoalsDashboardView(coordinator: model.goals)
        }
    }
}

// MARK: - Sidebar Tab Enum

/// Moved to file scope (was previously nested inside `ContentView`).
/// Nesting types isn't itself wrong, but the stray `#Preview` block that
/// used to live *after* this enum, still inside the struct's braces, was —
/// `#Preview` must be a top-level declaration, and having it inside a type
/// body is what produced the "circular reference expanding macro" and the
/// unrelated-looking `frame` errors.
enum SidebarTab: String, CaseIterable {
    case controls, stress, emotions, game, history, insights, goals

    var label: String { rawValue.capitalized }

    var icon: String {
        switch self {
        case .controls: return "gear"
        case .stress: return "chart.line.uptrend.xyaxis"
        case .emotions: return "brain.head.profile"
        case .game: return "gamecontroller.fill"
        case .history: return "clock.arrow.circlepath"
        case .insights: return "lightbulb"
        case .goals: return "target"    
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environmentObject(AppModel())
}
