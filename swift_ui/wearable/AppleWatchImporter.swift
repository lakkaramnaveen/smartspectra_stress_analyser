import Foundation
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif

/// The format a companion iOS app — one with real HealthKit access —
/// would need to write for its Watch-sourced heart rate to make it into
/// this Mac app.
///
/// This Mac app cannot read from a paired Apple Watch itself.
/// `WatchConnectivity` requires an iPhone-Watch pairing relationship,
/// which is a phone-and-watch concept at the hardware/OS level — a Mac
/// cannot have a paired Watch, the same structural reason HealthKit
/// itself is unavailable here. The only honest path is the same shape
/// as `HealthSync`'s export, run in reverse: a companion iOS app
/// produces a file in this format, and this import reads it.
struct WatchImportPayload: Codable, Sendable {
    let samples: [WatchHeartRateSample]
}

struct WatchHeartRateSample: Codable, Sendable {
    let bpm: Double
    let timestamp: Date
}

enum AppleWatchImporter {
    #if os(macOS)
    @MainActor
    static func importWithOpenPanel(onComplete: @escaping ([WearableReading]) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        panel.begin { response in
            guard response == .OK, let url = panel.url,
                  let data = try? Data(contentsOf: url) else {
                onComplete([])
                return
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            guard let payload = try? decoder.decode(WatchImportPayload.self, from: data) else {
                onComplete([])
                return
            }

            // A fixed confidence, not a measured one — there's no
            // per-sample reliability signal available in an imported
            // file the way there is for the camera's own session
            // statistics. Watch PPG is generally well-validated at rest,
            // which is why this sits reasonably high rather than at a
            // guess in the middle, but it remains an assumption, stated
            // as one, not a derived number.
            let readings = payload.samples.map {
                WearableReading(source: .appleWatch, bpm: $0.bpm, timestamp: $0.timestamp, confidence: 0.85)
            }
            onComplete(readings)
        }
    }
    #endif
}
