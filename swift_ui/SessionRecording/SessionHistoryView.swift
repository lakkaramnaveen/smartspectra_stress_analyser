import SwiftUI

// MARK: - View Model

/// Thin adapter between `SessionStoring` and SwiftUI. Owns no business
/// logic beyond "refresh the list, load one on demand, delete one" —
/// everything else lives in the store or the model layer.
@MainActor
final class SessionHistoryViewModel: ObservableObject {
    @Published private(set) var summaries: [SessionSummary] = []

    private let store: SessionStoring

    init(store: SessionStoring = FileSessionStore()) {
        self.store = store
        refresh()
    }

    func refresh() {
        summaries = store.loadSummaries()
    }

    func delete(_ summary: SessionSummary) {
        try? store.delete(id: summary.id)
        refresh()
    }

    func load(_ summary: SessionSummary) -> SessionRecording? {
        try? store.load(id: summary.id)
    }
}

// MARK: - History View

struct SessionHistoryView: View {
    @StateObject private var viewModel: SessionHistoryViewModel
    @State private var selectedSummary: SessionSummary?

    init(store: SessionStoring = FileSessionStore()) {
        _viewModel = StateObject(wrappedValue: SessionHistoryViewModel(store: store))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Session History")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("\(viewModel.summaries.count) recorded sessions")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
            }

            if viewModel.summaries.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(viewModel.summaries) { summary in
                            Button {
                                selectedSummary = summary
                            } label: {
                                SessionSummaryRow(summary: summary)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    viewModel.delete(summary)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(20)
        .sheet(item: $selectedSummary) { summary in
            if let recording = viewModel.load(summary) {
                SessionReplayView(recording: recording)
                    .frame(minWidth: 480, minHeight: 560)
            }
        }
        .onAppear { viewModel.refresh() }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "clock.badge.questionmark")
                .font(.system(size: 32))
                .foregroundStyle(.white.opacity(0.4))
            Text("No sessions recorded yet")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))
            Text("Start a session from Controls to begin recording.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - Row

private struct SessionSummaryRow: View {
    let summary: SessionSummary

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(summary.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)

                Text("\(summary.difficulty.capitalized) · \(DurationFormatter.mmss(summary.duration)) · \(summary.snapshotCount) samples")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("Peak")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.5))
                Text(String(format: "%.0f%%", summary.peakStress * 100))
                    .font(.callout.weight(.bold))
                    .foregroundStyle(StressLevel.classify(summary.peakStress).color)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .cornerRadius(10)
    }
}

#Preview {
    let store = InMemorySessionStore()
    let sample = SessionRecording(
        difficulty: "medium",
        snapshots: (0..<30).map { i in
            SessionSnapshot(
                timestamp: Date().addingTimeInterval(Double(i)),
                stressScore: Double.random(in: 0.2...0.8),
                heartRate: Double.random(in: 65...95),
                breathingRate: Double.random(in: 12...20),
                eda: Double.random(in: 0.01...0.08),
                emotionalState: "Calm",
                gazeConfidence: 0.9
            )
        }
    )
    try? store.save(sample)

    return SessionHistoryView(store: store)
        .frame(width: 360, height: 500)
        .background(BrandColor.slate)
}
