import SwiftUI

/// Root view for the Composure workspace.
///
/// Layout is a responsive two-pane split: camera workspace on the left,
/// tabbed sidebar on the right. Three overlays sit above that split in
/// the root `ZStack`, ordered by how much they should interrupt:
///
///   1000 — Balloon Hunt (fullscreen, takes over completely)
///    500 — Predictive stress alert (banner, non-blocking)
///    100 — Breathing pacer (modal-ish, but dismissible)
///
/// All logic lives in `AppModel` and the coordinators it composes;
/// this file is layout and routing only.
struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    @State private var showGameFullscreen = false
    @State private var activeSidebarTab: SidebarTab = .controls

    var body: some View {
        ZStack {
            splitLayout
            gameOverlay
            focusOverlay
            breathingOverlay
            alertOverlay
        }
        .animation(.easeInOut, value: showGameFullscreen)
        .animation(.spring(response: 0.4), value: model.prediction.activeAlert)
        .animation(.easeInOut, value: model.breathing.activeTechnique)
        .animation(.easeInOut, value: model.focus.isActive) 
    }

    // MARK: - Split Layout

    private var splitLayout: some View {
        HStack(spacing: 0) {
            mainWorkspace
                .frame(maxWidth: .infinity)

            Divider()

            sidebarPanel
                .frame(minWidth: 320, maxWidth: 500)
        }
    }

    // MARK: - Overlays

    /// Fullscreen eye-tracking game. Highest z-order — while it's up,
    /// nothing else should be competing for attention.
    @ViewBuilder
    private var gameOverlay: some View {
        if showGameFullscreen {
            BalloonHuntGameView()
                .environmentObject(model)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                .zIndex(1000)
        }
    }
    
    @ViewBuilder
    private var focusOverlay: some View {
        if model.focus.isActive {
            FocusOverlayView(coordinator: model.focus)
                .transition(.opacity)
                .zIndex(300)
        }
    }

    /// Guided breathing pacer.
    ///
    /// Driven entirely by `model.breathing.activeTechnique`, which is the
    /// single entry point for every way a session can begin: the
    /// automatic stress-threshold trigger, "Start breathing" on a
    /// predictive alert, and "Try it" in the technique library all set
    /// that one property. Routing them through a single source of truth
    /// avoids the classic bug where one path shows the overlay and
    /// another silently doesn't.
    @ViewBuilder
    private var breathingOverlay: some View {
        if let technique = model.breathing.activeTechnique {
            BreathingPacerView(
                technique: technique,
                onDismiss: { model.dismissBiofeedback() },
                onCompleted: { model.breathing.recordCompletion(of: $0) }
            )
            .environmentObject(model)
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
            .zIndex(100)
        }
    }

    /// Predictive stress alert. Deliberately a top banner rather than a
    /// modal — it's a nudge, and a nudge that blocks the interface is
    /// just an interruption.
    @ViewBuilder
    private var alertOverlay: some View {
        if let alert = model.prediction.activeAlert {
            VStack {
                StressAlertBanner(
                    alert: alert,
                    onDismiss: { model.prediction.dismissAlert() },
                    onStartBreathing: { model.beginBreathingManually() }
                )
                .frame(maxWidth: 520)
                .padding(.horizontal, 24)
                .padding(.top, 16)

                Spacer()
            }
            .transition(.move(edge: .top).combined(with: .opacity))
            .zIndex(500)
        }
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
                cameraPlaceholder
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

    private var cameraPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "video.slash")
                .font(.system(size: 44))
            Text("Camera offline")
                .font(.title3)
        }
        .foregroundStyle(.secondary)
    }

    private var validationPill: some View {
        Text(model.validationStatus.isEmpty ? "Waiting…" : model.validationStatus)
            .font(.callout.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Sidebar

    private var sidebarPanel: some View {
        VStack(spacing: 0) {
            tabBar

            Divider()

            sidebarContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(BrandColor.slate)
    }

    /// Horizontally scrolling tab strip.
    ///
    /// Two things worth knowing about the sizing here:
    ///
    /// **Fixed icon box.** SF Symbols have differing intrinsic aspect
    /// ratios — `chart.xyaxis.line` is far wider than `gearshape` at the
    /// same point size. A shared `.font(...)` normalises glyph *height*
    /// but leaves the layout boxes uneven, which is what makes a tab
    /// strip look subtly misaligned. Wrapping each glyph in a fixed
    /// square fixes it.
    ///
    /// **Scrolling rather than squeezing.** Eight tabs divided into a
    /// 320pt sidebar is ~34pt each, which crushes labels like "Controls"
    /// and "Insights" even with `minimumScaleFactor`. Giving each tab a
    /// real minimum width and letting the strip scroll keeps every label
    /// legible at any sidebar width, and degrades gracefully if more
    /// tabs get added later.
    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(SidebarTab.allCases, id: \.self) { tab in
                    tabButton(for: tab)
                }
            }
            .padding(8)
        }
        .background(Color.white.opacity(0.04))
    }

    private func tabButton(for tab: SidebarTab) -> some View {
        let isActive = activeSidebarTab == tab

        return Button {
            activeSidebarTab = tab
        } label: {
            VStack(spacing: 5) {
                Image(systemName: tab.icon)
                    .font(.system(size: 15, weight: .semibold))
                    // Uniform layout box — see the note on `tabBar`.
                    .frame(
                        width: SidebarMetrics.iconBox,
                        height: SidebarMetrics.iconBox
                    )

                Text(tab.label)
                    .font(.system(size: 9, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize()
            }
            .frame(minWidth: SidebarMetrics.tabMinWidth)
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
            .foregroundStyle(isActive ? BrandColor.primaryBlue : .white.opacity(0.5))
            // Without this the tap target is only the glyph and label
            // themselves, not the padded area around them.
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .background(isActive ? Color.white.opacity(0.10) : Color.clear)
        .cornerRadius(8)
        .help(tab.helpText)
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

        case .breathing:
            BreathingLibraryView(coordinator: model.breathing)

        case .game:
            GameTabView(showGameFullscreen: $showGameFullscreen)
                .environmentObject(model)

        case .goals:
            GoalsDashboardView(coordinator: model.goals)

        case .insights:
            InsightsDashboardView()

        case .history:
            SessionHistoryView()
            
        case .focus:
            FocusTabView(coordinator: model.focus)
            
        }
    }
}

// MARK: - Sidebar Metrics

/// Shared sizing constants for the tab strip. Centralised so icon and
/// tab dimensions stay in step if the strip is ever restyled.
enum SidebarMetrics {
    /// Uniform square each tab glyph is centred in.
    static let iconBox: CGFloat = 22

    /// Minimum width per tab. Sized so the longest label ("Controls")
    /// fits without truncating; the strip scrolls rather than squeezing.
    static let tabMinWidth: CGFloat = 52
}

// MARK: - Sidebar Tab

enum SidebarTab: String, CaseIterable {
    case controls
    case stress
    case emotions
    case breathing
    case focus
    case game
    case goals
    case insights
    case history

    var label: String {
        switch self {
        case .controls:  return "Controls"
        case .stress:    return "Stress"
        case .emotions:  return "Emotions"
        case .breathing: return "Breathe"
        case .focus: return "Focus"
        case .game:      return "Game"
        case .goals:     return "Goals"
        case .insights:  return "Insights"
        case .history:   return "History"
        }
    }

    /// Tooltip on hover. Cheap way to make an icon-and-tiny-label strip
    /// discoverable without widening it.
    var helpText: String {
        switch self {
        case .controls:  return "Session controls and API key"
        case .stress:    return "Live stress trajectory"
        case .emotions:  return "Detected emotional state"
        case .breathing: return "Breathing techniques"
        case .focus: return "timer"
        case .game:      return "Balloon Hunt eye-tracking game"
        case .goals:     return "Goals, streaks, and achievements"
        case .insights:  return "Patterns across your sessions"
        case .history:   return "Past session recordings"
        }
    }

    /// Symbols chosen for consistent visual weight as well as meaning.
    ///
    /// Two deliberate substitutions: `chart.xyaxis.line` replaces
    /// `chart.line.uptrend.xyaxis` (same concept, far closer in width to
    /// its neighbours), and the set is uniformly outline-weight rather
    /// than mixing filled and outline glyphs, which reads as
    /// inconsistent when they sit side by side.
    var icon: String {
        switch self {
        case .controls:  return "gearshape"
        case .stress:    return "chart.xyaxis.line"
        case .emotions:  return "brain.head.profile"
        case .breathing: return "wind"
        case .focus: return "Timed work blocks with quiet monitoring"
        case .game:      return "gamecontroller"
        case .goals:     return "target"
        case .insights:  return "lightbulb"
        case .history:   return "clock.arrow.circlepath"
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    ContentView()
        .environmentObject(AppModel())
        .frame(width: 1100, height: 720)
}
#endif
