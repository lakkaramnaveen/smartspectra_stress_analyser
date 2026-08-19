import AppKit

/// Plays a short system sound when a predictive stress alert fires.
///
/// Deliberately does not re-detect stress peaks itself.
/// `StressPredictionCoordinator` already does that — hysteresis,
/// cooldown, confidence gating, all of it — and firing a sound from a
/// second, independent threshold check would risk the two disagreeing
/// about when a "peak" actually happened. This only ever reacts to the
/// same `activeAlert` transition the visual banner already reacts to.
enum SoundAlertPlayer {
    static func playAlertSound() {
        NSSound(named: "Glass")?.play()
    }
}
