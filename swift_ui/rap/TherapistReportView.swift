import SwiftUI

struct TherapistReportView: View {
    @ObservedObject var reportCoordinator: TherapistReportCoordinator
    @ObservedObject var notesCoordinator: SessionNotesCoordinator
    @ObservedObject var pulseCoordinator: WellnessPulseCoordinator

    @State private var activeTab: ProviderReportTab = .report
    @State private var showingPreviewSheet = false
    @State private var newNoteText = ""

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $activeTab) {
                ForEach(ProviderReportTab.allCases, id: \.self) { tab in
                    Text(tab.label).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider().opacity(0.3)

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    // Only for Report/Notes — the therapist-specific
                    // wording ("HIPAA," "ask your provider") is the
                    // wrong context for Wellness Pulse, which has its
                    // own, differently-scoped notice built in below.
                    if activeTab != .wellnessPulse {
                        disclosureCard
                    }

                    switch activeTab {
                    case .report:
                        reportBuilderSection
                    case .notes:
                        notesSection
                    case .wellnessPulse:
                        WellnessPulseView(coordinator: pulseCoordinator)
                    }
                }
                .padding(Spacing.xl)
            }
        }
        .sheet(isPresented: $showingPreviewSheet) {
            if let markdown = reportCoordinator.previewMarkdown {
                PreviewSheet(markdown: markdown) {
                    showingPreviewSheet = false
                    reportCoordinator.export()
                }
                .frame(minWidth: 480, minHeight: 560)
            }
        }
    }

    // MARK: - Disclosure

    /// Leads the view, exactly like `HealthSyncView`'s platform notice —
    /// except the constraint here is legal and ethical, not technical,
    /// which if anything makes it more important to state before any
    /// controls rather than after them.
    private var disclosureCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "exclamationmark.shield")
                    .foregroundStyle(BrandColor.amber)
                Text("Read this before sharing anything")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
            }

            Text("This app is not a HIPAA-covered entity or business associate, and nothing it generates is \"HIPAA-compliant\" — that's a legal status this app can't grant. There's no built-in sharing channel here: this only creates a plain, unencrypted file on your Mac. What you do with it — email it, upload it to your provider's patient portal, print it — is entirely your choice.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)

            Text("If your provider's practice has a secure way they'd like to receive information, that's almost always the right channel — ask them, rather than defaulting to email.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.lg)
        .background(BrandColor.amber.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(BrandColor.amber.opacity(0.3), lineWidth: 1)
        )
        .cornerRadius(12)
    }

    // MARK: - Report Builder

    private var reportBuilderSection: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            dateRangeCard
            sectionsCard
            identityCard
            contextCard
            generateButton

            if let exported = reportCoordinator.lastExportedAt {
                Text("Last exported \(exported.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    private var dateRangeCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Period").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)

            HStack(spacing: Spacing.sm) {
                ForEach([ReportDateRange.lastTwoWeeks, .lastMonth, .lastThreeMonths], id: \.label) { range in
                    rangeButton(range)
                }
            }
        }
        .padding(Spacing.lg)
        .background(Color.white.opacity(0.04))
        .cornerRadius(12)
    }

    private func rangeButton(_ range: ReportDateRange) -> some View {
        let isSelected = reportCoordinator.config.dateRange == range
        return Button {
            reportCoordinator.config.dateRange = range
        } label: {
            Text(range.label)
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .foregroundStyle(isSelected ? .white : .white.opacity(0.6))
                .background(isSelected ? BrandColor.primaryBlue.opacity(0.3) : Color.white.opacity(0.05))
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    private var sectionsCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("What to include").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)

            ForEach(ReportSection.allCases) { section in
                Toggle(isOn: sectionBinding(section)) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(section.label).font(.caption.weight(.semibold)).foregroundStyle(.white)
                        Text(section.detail).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                    }
                }
                .toggleStyle(.switch)
                .tint(BrandColor.primaryBlue)
            }
        }
        .padding(Spacing.lg)
        .background(Color.white.opacity(0.04))
        .cornerRadius(12)
    }

    private func sectionBinding(_ section: ReportSection) -> Binding<Bool> {
        Binding(
            get: { reportCoordinator.config.includedSections.contains(section) },
            set: { included in
                if included {
                    reportCoordinator.config.includedSections.insert(section)
                } else {
                    reportCoordinator.config.includedSections.remove(section)
                }
            }
        )
    }

    /// The toggle most likely to be misread, so its caveat sits right
    /// beside it rather than in a footer someone may never scroll to.
    private var identityCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Toggle(isOn: $reportCoordinator.config.includeIdentifyingHeader) {
                Text("Include my name in the header")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .toggleStyle(.switch)
            .tint(BrandColor.primaryBlue)

            Text("Turning this off only removes your name from the document's header — it doesn't anonymize the data. A report of your own patterns, handed to your own provider, is identifiable to them by its content regardless. This matters if the file might reach someone who isn't already your provider; it doesn't do much for sharing directly with them.")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.lg)
        .background(Color.white.opacity(0.04))
        .cornerRadius(12)
    }

    private var contextCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Context for your provider (optional)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
            TextField("e.g. \"For our check-in on the 14th\"", text: $reportCoordinator.config.providerContext)
                .textFieldStyle(.roundedBorder)
        }
        .padding(Spacing.lg)
        .background(Color.white.opacity(0.04))
        .cornerRadius(12)
    }

    private var generateButton: some View {
        Button {
            Task {
                await reportCoordinator.generatePreview()
                showingPreviewSheet = true
            }
        } label: {
            if reportCoordinator.isGenerating {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity)
            } else {
                Label("Preview report", systemImage: "doc.text.magnifyingglass")
                    .font(.callout.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(BrandColor.primaryBlue)
        .disabled(reportCoordinator.isGenerating || reportCoordinator.config.includedSections.isEmpty)
    }

    // MARK: - Notes

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("New note").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                TextEditor(text: $newNoteText)
                    .frame(height: 80)
                    .padding(6)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(8)
                Button("Save note") {
                    notesCoordinator.add(text: newNoteText)
                    newNoteText = ""
                }
                .buttonStyle(.bordered)
                .disabled(newNoteText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(Spacing.lg)
            .background(Color.white.opacity(0.04))
            .cornerRadius(12)

            if !notesCoordinator.notes.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    ForEach(notesCoordinator.notes) { note in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(note.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.5))
                            Text(note.text)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.85))
                        }
                        .padding(Spacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.04))
                        .cornerRadius(10)
                        .contextMenu {
                            Button(role: .destructive) { notesCoordinator.delete(note) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Preview Sheet

/// Shows exactly what's about to be exported before it's exported —
/// nothing generated by this feature reaches disk without the person
/// seeing it in full first.
private struct PreviewSheet: View {
    let markdown: String
    let onExport: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack {
                Text("Preview").font(.title3.weight(.bold)).foregroundStyle(.white)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }

            ScrollView {
                Text(markdown)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .padding(Spacing.md)
            .background(Color.white.opacity(0.04))
            .cornerRadius(10)

            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Export…") {
                    dismiss()
                    onExport()
                }
                .buttonStyle(.borderedProminent)
                .tint(BrandColor.primaryBlue)
            }
        }
        .padding(Spacing.xl)
        .background(BrandColor.slate)
    }
}

// MARK: - Sub-tab

/// Report configuration, note-taking, and the opt-in Wellness Pulse
/// export live behind one internal picker, the same way Practice groups
/// Breathe/Meditate/Focus/Art — three fewer top-level tabs than treating
/// these as separate entries would have cost.
enum ProviderReportTab: String, CaseIterable {
    case report
    case notes
    case wellnessPulse

    var label: String {
        switch self {
        case .report: return "Report"
        case .notes: return "Notes"
        case .wellnessPulse: return "Org Pulse"
        }
    }
}

#if DEBUG
#Preview {
    let profile = UserProfile.default
    let sessionStore = InMemorySessionStore()
    return TherapistReportView(
        reportCoordinator: TherapistReportCoordinator(
            profile: profile,
            sessionStore: sessionStore,
            goalsStore: InMemoryGoalsStore(),
            sleepStore: InMemorySleepStore(),
            notesStore: InMemorySessionNoteStore()
        ),
        notesCoordinator: SessionNotesCoordinator(store: InMemorySessionNoteStore()),
        pulseCoordinator: WellnessPulseCoordinator(
            store: InMemoryWellnessPulseStore(),
            sessionStore: sessionStore
        )
    )
    .frame(width: 440, height: 800)
    .background(BrandColor.slate)
}
#endif
