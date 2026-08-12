import SwiftUI

/// Root view for the Composure workspace.
///
/// Layout is a responsive two-pane split: camera workspace on the left,
/// tabbed sidebar on the right. Five overlays sit above that split in
/// the root `ZStack`. `zIndex` — not declaration order — determines what
/// covers what, ordered by how completely each should take over:
///
///   1000 — Balloon Hunt (fullscreen game)
///    500 — Predictive stress alert (top banner, non-blocking)
///    400 — Meditation player
///    300 — Focus timer
///    100 — Breathing pacer
///
/// The alert sits deliberately *above* the practice overlays: it's a
/// banner pinned to the top edge, so it can coexist with them rather
/// than being buried. Everything else is mutually exclusive in practice.
///
/// All logic lives in `AppModel` and the coordinators it composes; this
/// file is layout and routing only.
struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    @State private var showGameFullscreen = false
    @State private var activeSidebarTab: SidebarTab = .controls
    @State private var activePracticeTab: PracticeTab = .breathing

    var body: some View {
        ZStack {
            splitLayout

            gameOverlay
            alertOverlay
            meditationOverlay
            focusOverlay
            breathingOverlay
        }
        .animation(.easeInOut, value: showGameFullscreen)
        .animation(.spring(response: 0.4), value: model.prediction.activeAlert)
        .animation(.easeInOut, value: model.breathing.activeTechnique)
        .animation(.easeInOut, value: model.focus.isActive)
        .animation(.easeInOut, value: model.meditation.activeMeditation)
        // Summary sheets live on the root, not on `mainWorkspace`.
        // Attached to a subview they'd present from something that may
        // be fully covered by an overlay at the moment the sheet fires.
        .sheet(item: meditationSummaryBinding) { summary in
            MeditationSummaryView(summary: summary) {
                model.meditation.dismissSummary()
            }
        }
        .sheet(item: focusSummaryBinding) { summary in
            FocusSummaryView(summary: summary) {
                model.focus.dismissSummary()
            }
        }
    }

    // MARK: - Bindings into child coordinators
    //
    // `$model.meditation.pendingSummary` doesn't compile: the coordinator
    // properties on `AppModel` are `let`, so SwiftUI can't synthesise a
    // write-back path through them — even though the property at the end
    // of that path is perfectly settable.
    //
    // Making the coordinators `var` would silence the error but is the
    // wrong fix. They're dependencies, not state: nothing should ever
    // swap which coordinator the model points at, and `let` is what says
    // so. An explicit `Binding` reads and writes the child directly and
    // leaves that guarantee intact.

    private var meditationSummaryBinding: Binding<MeditationSummary?> {
        Binding(
            get: { model.meditation.pendingSummary },
            set: { model.meditation.pendingSummary = $0 }
        )
    }

    private var focusSummaryBinding: Binding<FocusSummary?> {
        Binding(
            get: { model.focus.pendingSummary },
            set: { model.focus.pendingSummary = $0 }
        )
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

    @ViewBuilder
    private var meditationOverlay: some View {
        if let active = model.meditation.activeMeditation {
            MeditationPlayerView(coordinator: model.meditation, meditation: active)
                .transition(.opacity)
                .zIndex(400)
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
    /// **Fixed icon box.** SF Symbols have differing intrinsic aspect
    /// ratios — `chart.xyaxis.line` is far wider than `gearshape` at the
    /// same point size. A shared `.font(...)` normalises glyph *height*
    /// but leaves the layout boxes uneven, which is what makes a tab
    /// strip look subtly misaligned. Wrapping each glyph in a fixed
    /// square fixes it.
    ///
    /// **Scrolling rather than squeezing.** Each tab gets a real minimum
    /// width and the strip scrolls, so labels stay legible at any sidebar
    /// width rather than being crushed by `minimumScaleFactor`.
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

        case .practice:
            practicePane

        case .game:
            GameTabView(showGameFullscreen: $showGameFullscreen)
                .environmentObject(model)

        case .goals:
            GoalsDashboardView(coordinator: model.goals)

        case .insights:
            InsightsDashboardView()

        case .history:
            SessionHistoryView()
        }
    }

    // MARK: - Practice Pane

    /// Breathing, meditation, and focus grouped behind one tab.
    ///
    /// Ten top-level tabs is past the point where a strip gets scanned
    /// rather than read. These three are the same category from the
    /// user's side — deliberate practices you choose to start — so a
    /// segmented control inside one tab is both shorter and a better
    /// match for how they're actually thought about.
    private var practicePane: some View {
        VStack(spacing: 0) {
            Picker("", selection: $activePracticeTab) {
                ForEach(PracticeTab.allCases, id: \.self) { tab in
                    Text(tab.label).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider().opacity(0.3)

            switch activePracticeTab {
            case .breathing:
                BreathingLibraryView(coordinator: model.breathing)
            case .meditation:
                MeditationLibraryView(coordinator: model.meditation)
            case .focus:
                FocusTabView(coordinator: model.focus)
            }
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

// MARK: - Practice Tab

enum PracticeTab: String, CaseIterable {
    case breathing
    case meditation
    case focus

    var label: String {
        switch self {
        case .breathing:  return "Breathe"
        case .meditation: return "Meditate"
        case .focus:      return "Focus"
        }
    }
}

// MARK: - Sidebar Tab

enum SidebarTab: String, CaseIterable {
    case controls
    case stress
    case emotions
    case practice
    case game
    case goals
    case insights
    case history

    var label: String {
        switch self {
        case .controls: return "Controls"
        case .stress:   return "Stress"
        case .emotions: return "Emotions"
        case .practice: return "Practice"
        case .game:     return "Game"
        case .goals:    return "Goals"
        case .insights: return "Insights"
        case .history:  return "History"
        }
    }

    /// Tooltip on hover. Cheap way to make an icon-and-tiny-label strip
    /// discoverable without widening it.
    var helpText: String {
        switch self {
        case .controls: return "Session controls and API key"
        case .stress:   return "Live stress trajectory"
        case .emotions: return "Detected emotional state"
        case .practice: return "Breathing, meditation, and focus blocks"
        case .game:     return "Balloon Hunt eye-tracking game"
        case .goals:    return "Goals, streaks, and achievements"
        case .insights: return "Patterns across your sessions"
        case .history:  return "Past session recordings"
        }
    }

    /// SF Symbol names.
    ///
    /// Every value here must be a real symbol name — an invalid string
    /// renders as an empty gap with no compiler warning, which is easy
    /// to miss in review. (That's exactly how the Focus tab ended up
    /// blank: its `icon` was returning a sentence.)
    var icon: String {
        switch self {
        case .controls: return "gearshape"
        case .stress:   return "chart.xyaxis.line"
        case .emotions: return "brain.head.profile"
        case .practice: return "figure.mind.and.body"
        case .game:     return "gamecontroller"
        case .goals:    return "target"
        case .insights: return "lightbulb"
        case .history:  return "clock.arrow.circlepath"
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
