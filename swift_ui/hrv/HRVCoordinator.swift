import Foundation
import SwiftUI

// MARK: - Store

protocol HRVStoring {
    func load() -> [HRVMeasurement]
    func save(_ measurements: [HRVMeasurement]) throws
}

final class FileHRVStore: HRVStoring {
    private let fileURL: URL

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    init(appSupportSubdirectory: String = "Composure") {
        let fileManager = FileManager.default
        let base = fileManager
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? fileManager.temporaryDirectory

        let directory = base.appendingPathComponent(appSupportSubdirectory, isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        fileURL = directory.appendingPathComponent("hrv.json")
    }

    func load() -> [HRVMeasurement] {
        guard let data = try? Data(contentsOf: fileURL),
              let measurements = try? decoder.decode([HRVMeasurement].self, from: data) else {
            return []
        }
        return measurements
    }

    func save(_ measurements: [HRVMeasurement]) throws {
        // Cap stored history. Measurements arrive roughly once a minute
        // during a session, so an uncapped file grows without bound.
        let capped = Array(measurements.suffix(2000))
        let data = try encoder.encode(capped)
        try data.write(to: fileURL, options: .atomic)
    }
}

final class InMemoryHRVStore: HRVStoring {
    private var measurements: [HRVMeasurement]

    init(measurements: [HRVMeasurement] = []) { self.measurements = measurements }
    func load() -> [HRVMeasurement] { measurements }
    func save(_ measurements: [HRVMeasurement]) throws { self.measurements = measurements }
}

// MARK: - Coordinator

@MainActor
final class HRVCoordinator: ObservableObject {

    @Published private(set) var latestReading: HRVReading?
    @Published private(set) var quality: BeatSignalQuality = .unusable
    @Published private(set) var sampleRateHz: Double = 0
    @Published private(set) var history: [HRVMeasurement] = []

    /// Correlation between variability and stress, once there's enough
    /// paired data. `nil` means "not enough to say", never "no effect".
    @Published private(set) var stressCorrelation: Double?

    private var detector: BeatDetector
    private var analyzer: HRVAnalyzer
    private let store: HRVStoring
    private let config: HRVConfig

    /// Stress scores keyed by minute, for pairing against measurements.
    private var stressByMinute: [Date: Double] = [:]

    private var lastBatchAt: Date?
    private var hasSeeded = false

    init(store: HRVStoring? = nil, config: HRVConfig = .default) {
        self.config = config
        self.store = store ?? FileHRVStore()
        self.detector = BeatDetector(config: config)
        self.analyzer = HRVAnalyzer(config: config)
    }

    // MARK: - Lifecycle

    func startSession() {
        detector.reset()
        analyzer.reset()
        latestReading = nil
        quality = .unusable
        lastBatchAt = nil
        stressByMinute.removeAll()

        seedHistoryIfNeeded()
    }

    func endSession() {
        persist()
        recomputeCorrelation()
    }

    /// Loads stored measurements once per launch so personal bands are
    /// available immediately rather than after twenty fresh windows.
    /// Deferred out of `init` because it touches disk.
    private func seedHistoryIfNeeded() {
        guard !hasSeeded else { return }
        hasSeeded = true

        let stored = store.load()
        analyzer.seedHistory(stored)
        history = stored
    }

    // MARK: - Ingestion

    /// Feed a waveform batch from the SDK's arterial pressure trace.
    ///
    /// This is the *only* usable source for beat intervals. Pulse-rate
    /// strings are averaged values with no beat-to-beat structure, and
    /// running variability maths over them produces a number unrelated to
    /// RMSSD.
    func ingestWaveform(_ samples: [Double], at timestamp: Date = Date()) {
        guard !samples.isEmpty else { return }

        let duration = lastBatchAt.map { timestamp.timeIntervalSince($0) }
        lastBatchAt = timestamp

        let result = detector.ingest(
            samples: samples,
            batchTimestamp: timestamp,
            batchDuration: duration
        )

        quality = result.quality
        sampleRateHz = result.sampleRateHz

        guard !result.intervals.isEmpty else { return }

        if let reading = analyzer.ingest(
            intervals: result.intervals,
            quality: result.quality,
            artefactRate: detector.artefactRate
        ) {
            latestReading = reading
            history = analyzer.recentHistory
        }
    }

    /// Record the current stress score so measurements can later be
    /// paired against it. Bucketed by minute — finer pairing would imply
    /// a temporal precision neither signal has.
    func noteStress(_ score: Double, at timestamp: Date = Date()) {
        let minute = Calendar.current.date(
            bySetting: .second, value: 0, of: timestamp
        ) ?? timestamp
        stressByMinute[minute] = score
    }

    // MARK: - Private

    private func recomputeCorrelation() {
        stressCorrelation = HRVAnalyzer.correlateWithStress(
            measurements: history
        ) { [weak self] timestamp in
            guard let self else { return nil }
            let minute = Calendar.current.date(
                bySetting: .second, value: 0, of: timestamp
            ) ?? timestamp
            return self.stressByMinute[minute]
        }
    }

    private func persist() {
        do {
            try store.save(history)
        } catch {
            print("HRVCoordinator: failed to persist — \(error.localizedDescription)")
        }
    }
}
