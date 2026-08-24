import SwiftUI

/// Root view for the Composure workspace.
///
/// Layout is a responsive two-pane split: camera workspace on the left,
/// tabbed sidebar on the right. Seven overlays sit above that split in
/// the root `ZStack`. `zIndex` — not declaration order — determines what
/// covers what, ordered by how completely each should take over:
///
///   1000 — Balloon Hunt (fullscreen game)
///    500 — Predictive stress alert (top banner)
///    400 — Meditation player (full)
///    300 — Focus timer (full)
///    250 — Desk-habit nudge (bottom-centre card)
///    200 — Recovery panel (bottom-trailing card)
///    100 — Breathing pacer (full)
///
/// The three cards (alert, nudge, recovery) are non-blocking and occupy
/// different screen edges, so they can coexist without collision. The
/// full overlays are mutually exclusive in practice.
///
/// All logic lives in `AppModel` and the coordinators it composes; this
/// file is layout and routing only.
struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var profiles: ProfileCoordinator

    @State private var showGameFullscreen = false
    @State private var activeSidebarTab: SidebarTab = .controls
    @State private var activePracticeTab: PracticeTab = .breathing
    @State private var activeWorkspaceTab: WorkspaceTab = .habits

    var body: some View {
        ZStack {
            splitLayout

            // Every overlay must be listed here. A `@ViewBuilder`
            // property that's declared but never composed compiles
            // cleanly and silently renders nothing — an easy thing to
            // miss when adding a feature.
            gameOverlay
            alertOverlay
            meditationOverlay
            focusOverlay
            ergonomicsOverlay
            recoveryOverlay
            breathingOverlay
        }
        .animation(.easeInOut, value: showGameFullscreen)
        .animation(.spring(response: 0.4), value: model.prediction.activeAlert)
        .onChange(of: model.prediction.activeAlert) { oldAlert, newAlert in
            // Reacts to the same transition the visual banner already
            // reacts to, rather than re-detecting stress peaks with a
            // second, independent threshold check.
            guard oldAlert == nil, newAlert != nil,
                  model.appPreferences.preferences.soundAlertsEnabled else { return }
            SoundAlertPlayer.playAlertSound()
        }
        .animation(.easeInOut, value: model.breathing.activeTechnique)
        .animation(.easeInOut, value: model.focus.isActive)
        .animation(.easeInOut, value: model.meditation.activeMeditation)
        .animation(.spring(response: 0.4), value: model.ergonomics.activeNudge)
        .animation(.spring(response: 0.45), value: model.recovery.state)
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

    /// Desk-habit nudge. Bottom-centre, so it doesn't compete with the
    /// stress alert at the top or the recovery panel at the trailing
    /// edge.
    @ViewBuilder
    private var ergonomicsOverlay: some View {
        if let nudge = model.ergonomics.activeNudge {
            VStack {
                Spacer()
                ErgonomicsNudgeBanner(
                    nudge: nudge,
                    onDismiss: { model.ergonomics.dismissNudge() },
                    onBreakTaken: { model.ergonomics.markBreakTaken() }
                )
                .frame(maxWidth: 460)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .zIndex(250)
        }
    }

    /// Recovery panel. A card rather than a modal on purpose — it
    /// appears shortly after a breathing session ends, and a second
    /// full-screen takeover there would be one interruption too many.
    @ViewBuilder
    private var recoveryOverlay: some View {
        if let state = model.recovery.state {
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    RecoveryPanel(
                        state: state,
                        hasSettled: model.recovery.hasSettled,
                        onDismiss: { model.recovery.dismiss() },
                        onStartBreathing: { model.beginBreathingManually() }
                    )
                    .padding(.trailing, 24)
                    .padding(.bottom, 24)
                }
            }
            .transition(.move(edge: .trailing).combined(with: .opacity))
            .zIndex(200)
        }
    }

    /// Guided breathing pacer.
    ///
    /// Driven entirely by `model.breathing.activeTechnique`, which is the
    /// single entry point for every way a session can begin: the
    /// automatic stress-threshold trigger, "Start breathing" on a
    /// predictive alert or the recovery panel, and "Try it" in the
    /// technique library all set that one property. Routing them through
    /// a single source of truth avoids the classic bug where one path
    /// shows the overlay and another silently doesn't.
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
            profileBar

            Divider()

            tabBar

            Divider()

            sidebarContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(BrandColor.slate)
    }

    /// Slim header identifying whose data is currently active, with a
    /// direct way back to the switcher. Kept intentionally minimal — a
    /// name, a colour, one button — since this sits above every tab and
    /// shouldn't compete with them for attention.
    private var profileBar: some View {
        HStack(spacing: Spacing.sm) {
            Circle()
                .fill(model.profile.colorTag.color.opacity(0.3))
                .frame(width: 20, height: 20)
                .overlay(
                    Text(model.profile.initial)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(model.profile.colorTag.color)
                )

            Text(model.profile.name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)

            Spacer()

            Button(action: switchProfile) {
                Text("Switch")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(BrandColor.teal)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// Ends any active session before handing off — switching profiles
    /// mid-session would otherwise leave a running camera engine and a
    /// live pacer overlay attached to a model the next profile's screen
    /// is about to replace out from under them.
    private func switchProfile() {
        if model.isRunning {
            model.stop()
        }
        profiles.requestSwitch()
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

        case .heart:
            HRVTabView(coordinator: model.hrv)

        case .desk:
            workspacePane

        case .rest:
            SleepTabView(coordinator: model.sleep)

        case .practice:
            practicePane

        case .game:
            GameTabView(showGameFullscreen: $showGameFullscreen)
                .environmentObject(model)

        case .coach:
            CoachTabView(coordinator: model.coach)

        case .goals:
            GoalsDashboardView(coordinator: model.goals)

        case .insights:
            // Passing `model.sessionStore` explicitly rather than
            // letting this default its own `FileSessionStore()` — the
            // default resolves to the unnamespaced "Composure/Sessions"
            // root, which is only correct for `UserProfile.default`. For
            // any other profile it would silently show the wrong
            // person's session history.
            InsightsDashboardView(store: model.sessionStore)

        case .history:
            SessionHistoryView(store: model.sessionStore)

        case .health:
            HealthSyncView(coordinator: model.healthSync)

        case .wearables:
            WearableTabView(coordinator: model.wearable, sessionStore: model.sessionStore)

        case .providerReport:
            TherapistReportView(
                reportCoordinator: model.therapistReport,
                notesCoordinator: model.sessionNotes,
                pulseCoordinator: model.wellnessPulse
            )

        case .triggers:
            AppUsageView(coordinator: model.appUsage, focus: model.focus)

        case .homeAutomation:
            HomeAutomationView(coordinator: model.homeAutomation)

        case .settings:
            SettingsView(coordinator: model.appPreferences)
        }
    }

    // MARK: - Practice Pane

    /// Breathing, meditation, and focus grouped behind one tab.
    ///
    /// These three are the same category from the user's side —
    /// deliberate practices you choose to start — so a segmented control
    /// inside one tab is both shorter and a better match for how they're
    /// actually thought about than three top-level entries.
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
            case .art:
                BiofeedbackArtView()
                    .environmentObject(model)
            }
        }
    }

    // MARK: - Workspace Pane

    /// Desk habits (screen time, neck strain) and environment (lighting,
    /// noise) grouped behind one tab, the same way Practice already
    /// groups its three. Both are "things about your physical setup"
    /// from the user's side, and this is a genuine consolidation, not
    /// just a smaller version of the tab-count problem — it's one fewer
    /// top-level entry than treating Environment separately would have
    /// cost, on top of the two features (Practice, Provider Report)
    /// that already applied the same restraint.
    private var workspacePane: some View {
        VStack(spacing: 0) {
            Picker("", selection: $activeWorkspaceTab) {
                ForEach(WorkspaceTab.allCases, id: \.self) { tab in
                    Text(tab.label).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider().opacity(0.3)

            // Not a shared outer ScrollView here: `ErgonomicsTabView`
            // already scrolls itself, and wrapping it in a second one
            // would nest two independently-scrolling regions. Each case
            // below scrolls exactly the way its own view expects to.
            switch activeWorkspaceTab {
            case .habits:
                ErgonomicsTabView(coordinator: model.ergonomics)
            case .environment:
                ScrollView {
                    EnvironmentSectionView(coordinator: model.environment)
                        .padding(Spacing.xl)
                }
            }
        }
    }
}

// MARK: - Workspace Tab

enum WorkspaceTab: String, CaseIterable {
    case habits
    case environment

    var label: String {
        switch self {
        case .habits:      return "Habits"
        case .environment: return "Environment"
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
    case art

    var label: String {
        switch self {
        case .breathing:  return "Breathe"
        case .meditation: return "Meditate"
        case .focus:      return "Focus"
        case .art:        return "Art"
        }
    }
}

// MARK: - Sidebar Tab

/// Eighteen tabs. Settings is a genuinely new category — a one-time
/// app-shell configuration screen, not a live signal, a practice, or a
/// retrospective view — so unlike the last several additions it doesn't
/// have a natural existing home to fold into. The Signals consolidation
/// (Stress, Emotions, Heart, Desk, Rest → one tab) would still bring
/// this to fourteen without hiding anything reachable today.
enum SidebarTab: String, CaseIterable {
    case controls
    case stress
    case emotions
    case heart
    case desk
    case rest
    case practice
    case game
    case coach
    case goals
    case insights
    case history
    case health
    case wearables
    case providerReport
    case triggers
    case homeAutomation
    case settings

    var label: String {
        switch self {
        case .controls:       return "Controls"
        case .stress:         return "Stress"
        case .emotions:       return "Emotions"
        case .heart:          return "Heart"
        case .desk:           return "Workspace"
        case .rest:           return "Rest"
        case .practice:       return "Practice"
        case .game:           return "Game"
        case .coach:          return "Coach"
        case .goals:          return "Goals"
        case .insights:       return "Insights"
        case .history:        return "History"
        case .health:         return "Health"
        case .wearables:      return "Wearables"
        case .providerReport: return "Provider"
        case .triggers:       return "Triggers"
        case .homeAutomation: return "Home"
        case .settings:       return "Settings"
        }
    }

    /// Tooltip on hover. Cheap way to make an icon-and-tiny-label strip
    /// discoverable without widening it.
    var helpText: String {
        switch self {
        case .controls: return "Session controls and API key"
        case .stress:   return "Live stress trajectory"
        case .emotions: return "Detected emotional state"
        case .heart:    return "Beat-to-beat variability from the pulse waveform"
        case .desk:     return "Screen time, breaks, lighting, and noise"
        case .rest:     return "Sleep log and how it lines up with your readings"
        case .practice: return "Breathing, meditation, and focus blocks"
        case .game:     return "Balloon Hunt eye-tracking game"
        case .coach:    return "Which techniques have actually worked for you"
        case .goals:    return "Goals, streaks, and achievements"
        case .insights: return "Patterns across your sessions"
        case .history:  return "Past session recordings"
        case .health:   return "Prepare data for Apple Health export"
        case .wearables: return "Cross-check against Oura or Apple Watch"
        case .providerReport: return "Prepare a summary to share with your provider"
        case .triggers: return "Which apps correlate with higher stress"
        case .homeAutomation: return "Trigger a Shortcut from your stress readings"
        case .settings: return "Appearance, sound, and launch behavior"
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
        case .heart:    return "heart.text.square"
        case .desk:     return "figure.seated.side"
        case .rest:     return "moon.zzz"
        case .practice: return "figure.mind.and.body"
        case .game:     return "gamecontroller"
        case .coach:    return "wand.and.stars"
        case .goals:    return "target"
        case .insights: return "lightbulb"
        case .history:  return "clock.arrow.circlepath"
        case .health:   return "tray.and.arrow.up"
        case .wearables: return "applewatch"
        case .providerReport: return "person.text.rectangle"
        case .triggers: return "macwindow"
        case .homeAutomation: return "house"
        case .settings: return "slider.horizontal.3"
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    ContentView()
        .environmentObject(AppModel())
        .environmentObject(ProfileCoordinator())
        .environmentObject(AppLockCoordinator(store: InMemoryAppLockCredentialStore(preconfiguredPasscode: "1234")))
        .frame(width: 1100, height: 720)
}
#endif
