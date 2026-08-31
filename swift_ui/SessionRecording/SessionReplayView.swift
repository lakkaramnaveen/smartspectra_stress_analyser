import SwiftUI

/// Timeline playback for a completed session: scrub to any point in time
/// to see the biometric snapshot closest to it, or press play to watch
/// the session unfold in real time.
///
/// Reuses `StressGraph` from `StressVisualizationView.swift` — no need
/// to duplicate the Canvas-drawing logic for a stress curve.
struct SessionReplayView: View {
    let recording: SessionRecording

    @Environment(\.dismiss) private var dismiss
    @State private var playbackOffset: TimeInterval = 0
    @State private var isPlaying = false
    @State private var playbackTask: Task<Void, Never>?

    private var sortedSnapshots: [SessionSnapshot] {
        recording.snapshots.sorted { $0.timestamp < $1.timestamp }
    }

    /// The snapshot whose timestamp is closest to (at or before) the
    /// current scrub position.
    private var currentSnapshot: SessionSnapshot? {
        guard !sortedSnapshots.isEmpty else { return nil }
        let targetTime = recording.startedAt.addingTimeInterval(playbackOffset)
        return sortedSnapshots.last { $0.timestamp <= targetTime } ?? sortedSnapshots.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            if let snapshot = currentSnapshot {
                metricsGrid(for: snapshot)
            } else {
                Text("No data captured for this session.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }

            stressTimelineChart

            scrubber

            transportControls

            Spacer(minLength: 0)
        }
        .padding(24)
        .background(BrandColor.slate)
        .onDisappear { playbackTask?.cancel() }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Session Replay")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                Text(recording.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }

            Spacer()

            Button {
                SessionCSVExporter.exportWithSavePanel(recording)
            } label: {
                Label("Export CSV", systemImage: "square.and.arrow.up")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
    }

    // MARK: - Metrics for the scrubbed moment

    private func metricsGrid(for snapshot: SessionSnapshot) -> some View {
        HStack(spacing: 12) {
            StatsCard(
                icon: "heart.fill",
                label: "Heart Rate",
                value: "\(Int(snapshot.heartRate)) bpm",
                color: BrandColor.coral
            )
            StatsCard(
                icon: "wind",
                label: "Breathing",
                value: "\(Int(snapshot.breathingRate)) rpm",
                color: BrandColor.mint
            )
            StatsCard(
                icon: "waveform.path.ecg",
                label: "Stress",
                value: String(format: "%.0f%%", snapshot.stressScore * 100),
                color: StressLevel.classify(snapshot.stressScore).color
            )
        }
    }

    // MARK: - Full-session stress curve with a playhead

    /// Fraction (0...1) of the way through the recording the playhead
    /// currently sits. Pulled out as its own property, rather than
    /// computed inline inside the view body, to keep each expression
    /// small enough for the type checker to solve quickly.
    private var playheadFraction: Double {
        guard recording.duration > 0 else { return 0 }
        return playbackOffset / recording.duration
    }

    private var stressTimelineChart: some View {
        GeometryReader { proxy in
            let playheadX: CGFloat = proxy.size.width * CGFloat(playheadFraction)

            ZStack(alignment: .leading) {
                StressGraph(
                    data: sortedSnapshots.map(\.stressScore),
                    color: BrandColor.teal
                )

                if recording.duration > 0 {
                    Rectangle()
                        .fill(Color.white.opacity(0.85))
                        .frame(width: 1.5)
                        .offset(x: playheadX)
                }
            }
        }
        .frame(height: 140)
        .padding(.vertical, 4)
    }

    // MARK: - Scrubber

    private var scrubber: some View {
        VStack(spacing: 6) {
            Slider(
                value: $playbackOffset,
                in: 0...max(recording.duration, 0.001)
            ) { editing in
                if editing { pausePlayback() }
            }
            .tint(BrandColor.teal)

            HStack {
                Text(DurationFormatter.mmss(playbackOffset))
                Spacer()
                Text(DurationFormatter.mmss(recording.duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.white.opacity(0.6))
        }
    }

    // MARK: - Transport controls

    private var transportControls: some View {
        HStack(spacing: 20) {
            Button {
                playbackOffset = 0
            } label: {
                Image(systemName: "backward.end.fill")
            }

            Button {
                isPlaying ? pausePlayback() : startPlayback()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
            }

            Button {
                playbackOffset = recording.duration
            } label: {
                Image(systemName: "forward.end.fill")
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }

    // MARK: - Playback loop

    private func startPlayback() {
        guard recording.duration > 0 else { return }
        if playbackOffset >= recording.duration { playbackOffset = 0 }

        isPlaying = true
        playbackTask?.cancel()
        playbackTask = Task {
            let tick: TimeInterval = 0.1
            while !Task.isCancelled, playbackOffset < recording.duration {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                playbackOffset = min(playbackOffset + tick, recording.duration)
            }
            isPlaying = false
        }
    }

    private func pausePlayback() {
        isPlaying = false
        playbackTask?.cancel()
    }
}

#if DEBUG
private func makePreviewSnapshot(at index: Int) -> SessionSnapshot {
    let time = Double(index)
    let stress: Double = 0.3 + 0.4 * sin(time / 10)
    let heartRate: Double = 70 + Double(index % 20)
    let breathingRate: Double = 14 + Double(index % 5)

    return SessionSnapshot(
        timestamp: Date().addingTimeInterval(time),
        stressScore: stress,
        heartRate: heartRate,
        breathingRate: breathingRate,
        eda: 0.02,
        emotionalState: "Focused",
        gazeConfidence: 0.85
    )
}

private func makePreviewRecording() -> SessionRecording {
    let snapshots: [SessionSnapshot] = (0..<120).map(makePreviewSnapshot)
    return SessionRecording(difficulty: "hard", snapshots: snapshots)
}

#Preview {
    SessionReplayView(recording: makePreviewRecording())
        .frame(width: 480, height: 560)
}
#endif
