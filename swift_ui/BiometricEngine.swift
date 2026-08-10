import AppKit
import Foundation

/// Mirrors `SmartSpectraRunnerDelegate` but with Swift-native types and no
/// Objective-C baggage, so downstream consumers (services, view models)
/// don't need to import AppKit/ObjC interop concepts directly.
protocol BiometricEngineDelegate: AnyObject {
    func biometricEngine(_ engine: BiometricEngine, didCaptureFrame image: NSImage)
    func biometricEngine(_ engine: BiometricEngine, didUpdateProcessingStatus processing: String, validationStatus: String)
    func biometricEngine(_ engine: BiometricEngine, didUpdateMetrics metrics: [String], timestampMicros: Int64)
    func biometricEngine(
        _ engine: BiometricEngine,
        didUpdateTraces breathing: [Double],
        arterialPressure: [Double],
        eda: [Double],
        timestampMicros: Int64
    )
    func biometricEngine(_ engine: BiometricEngine, didUpdateDiagnostics diagnostics: String)
    func biometricEngine(_ engine: BiometricEngine, didFailWith error: BiometricEngineError)
}

enum BiometricEngineError: LocalizedError {
    case sdkError(String)
    case missingCredential

    var errorDescription: String? {
        switch self {
        case .sdkError(let message):
            return message
        case .missingCredential:
            return "No SmartSpectra API key configured. Add one in Settings before starting a session."
        }
    }
}

/// Thin, testable wrapper around the Objective-C++ `SmartSpectraRunner`.
///
/// This exists so `AppModel`/view models never talk to the ObjC runner or
/// its delegate protocol directly — they depend on this Swift protocol
/// instead, which makes it possible to inject a fake engine in unit tests
/// and keeps the NSNumber/NSImage marshaling contained in one place.
protocol BiometricEngineProviding: AnyObject {
    var delegate: BiometricEngineDelegate? { get set }
    func start(apiKey: String) -> BiometricEngineError?
    func stop()
}

final class BiometricEngine: NSObject, BiometricEngineProviding, SmartSpectraRunnerDelegate {
    weak var delegate: BiometricEngineDelegate?

    private let runner = SmartSpectraRunner()

    override init() {
        super.init()
        runner.delegate = self
    }

    func start(apiKey: String) -> BiometricEngineError? {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .missingCredential }

        if let message = runner.start(withAPIKey: trimmed) {
            return .sdkError(message)
        }
        return nil
    }

    func stop() {
        runner.stop()
    }

    // MARK: - SmartSpectraRunnerDelegate (ObjC boundary — converts to Swift types immediately)

    func smartSpectraRunnerDidUpdateFrame(_ image: NSImage) {
        delegate?.biometricEngine(self, didCaptureFrame: image)
    }

    func smartSpectraRunnerDidUpdateStatus(_ processing: String, validation: String) {
        delegate?.biometricEngine(self, didUpdateProcessingStatus: processing, validationStatus: validation)
    }

    func smartSpectraRunnerDidUpdateMetrics(_ metrics: [String], timestampUs: Int64) {
        delegate?.biometricEngine(self, didUpdateMetrics: metrics, timestampMicros: timestampUs)
    }

    func smartSpectraRunnerDidUpdateBreathingTrace(
        _ breathingTrace: [NSNumber],
        arterialPressureTrace: [NSNumber],
        edaTrace: [NSNumber],
        timestampUs: Int64
    ) {
        delegate?.biometricEngine(
            self,
            didUpdateTraces: breathingTrace.map(\.doubleValue),
            arterialPressure: arterialPressureTrace.map(\.doubleValue),
            eda: edaTrace.map(\.doubleValue),
            timestampMicros: timestampUs
        )
    }

    func smartSpectraRunnerDidUpdateDiagnostics(_ diagnostics: String) {
        delegate?.biometricEngine(self, didUpdateDiagnostics: diagnostics)
    }

    func smartSpectraRunnerDidFail(_ message: String) {
        delegate?.biometricEngine(self, didFailWith: .sdkError(message))
    }
}
