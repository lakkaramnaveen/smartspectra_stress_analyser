import Foundation
import SwiftUI

@MainActor
final class TherapistReportCoordinator: ObservableObject {

    @Published var config = TherapistReportConfig()
    @Published private(set) var preview: TherapistReport?
    @Published private(set) var previewMarkdown: String?
    @Published private(set) var isGenerating = false
    @Published private(set) var isExporting = false
    @Published private(set) var lastExportedAt: Date?

    private let profile: UserProfile
    private let sessionStore: SessionStoring
    private let goalsStore: GoalsStoring
    private let sleepStore: SleepStoring
    private let notesStore: SessionNoteStoring
    private let builder = TherapistReportBuilder()
    private let renderer = TherapistReportRenderer()

    init(
        profile: UserProfile,
        sessionStore: SessionStoring,
        goalsStore: GoalsStoring? = nil,
        sleepStore: SleepStoring? = nil,
        notesStore: SessionNoteStoring? = nil
    ) {
        self.profile = profile
        self.sessionStore = sessionStore
        self.goalsStore = goalsStore ?? FileGoalsStore(appSupportSubdirectory: profile.storageRoot)
        self.sleepStore = sleepStore ?? FileSleepStore(appSupportSubdirectory: profile.storageRoot)
        self.notesStore = notesStore ?? FileSessionNoteStore(appSupportSubdirectory: profile.storageRoot)
    }

    /// Builds and renders a preview — always the step before export.
    /// There's no path in this coordinator that produces a file without
    /// the person first seeing exactly what's in it.
    func generatePreview() async {
        isGenerating = true
        defer { isGenerating = false }

        let recordings = sessionStore.loadSummaries().compactMap { try? sessionStore.load(id: $0.id) }
        let goalsState = goalsStore.load()
        let sleepEntries = sleepStore.load()
        let notes = notesStore.load()
        let currentConfig = config
        let currentProfile = profile
        let builder = self.builder
        let renderer = self.renderer

        let result = await Task.detached(priority: .utility) { () -> (TherapistReport, String) in
            let report = builder.build(
                config: currentConfig,
                profile: currentProfile,
                recordings: recordings,
                goalsState: goalsState,
                sleepEntries: sleepEntries,
                notes: notes
            )
            return (report, renderer.markdown(for: report))
        }.value

        preview = result.0
        previewMarkdown = result.1
    }

    func export() {
        guard let markdown = previewMarkdown else { return }
        isExporting = true

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let name = "composure-report-\(formatter.string(from: Date()))"

        TherapistReportExporter.exportWithSavePanel(markdown: markdown, suggestedName: name) { [weak self] success in
            self?.isExporting = false
            if success { self?.lastExportedAt = Date() }
        }
    }
}
