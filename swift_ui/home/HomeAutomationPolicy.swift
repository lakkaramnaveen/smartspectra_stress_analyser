import Foundation

/// Decides when a physical-world automation should fire — pure state
/// machine, same shape as `ErgonomicsNudgePolicy` and
/// `InterventionAlertPolicy`.
///
/// ## What this policy can and can't be responsible for
///
/// This decides *whether to ask* Shortcuts to run a scene. It has no
/// visibility into what that scene actually does — set a thermostat,
/// dim a light, lock a door — because Composure never sees inside the
/// Shortcut the person built. "Don't let the room get too cold" has to
/// be a limit the person builds into their own Shortcut (a temperature
/// floor, say), not something this code can enforce; there's nothing
/// here to enforce it *on*. What this policy *can* be responsible for
/// is not firing too often: sustained-duration and cooldown gates below
/// exist so a single noisy stress spike, or a few minutes hovering near
/// a threshold, doesn't fire a real-world action repeatedly.
struct HomeAutomationPolicy: Sendable {

    enum Trigger: Sendable {
        case calmScene
        case celebrateScene
    }

    /// How long stress must stay in the top band before the calm scene
    /// fires — long enough that a brief spike (someone walking past the
    /// camera, a moment of motion blur) can't trigger it alone.
    let sustainedHighDuration: TimeInterval

    /// Minimum gap between any two triggers, of either kind.
    let cooldown: TimeInterval

    private var highStreakStart: Date?
    private var lastCalmTriggerAt: Date?
    private var lastCelebrateTriggerAt: Date?

    init(sustainedHighDuration: TimeInterval = 90, cooldown: TimeInterval = 600) {
        self.sustainedHighDuration = sustainedHighDuration
        self.cooldown = cooldown
    }

    /// Call on every stress update. `hasSettled` is
    /// `RecoveryCoordinator`'s own existing determination of "calmed
    /// down from a peak" — reused rather than reimplemented, so there's
    /// one definition of "recovered" in this app, not two that could
    /// quietly disagree.
    mutating func ingest(stressScore: Double, hasSettled: Bool, now: Date = Date()) -> Trigger? {
        if StressLevel.classify(stressScore) == .critical {
            if highStreakStart == nil { highStreakStart = now }

            if let start = highStreakStart, now.timeIntervalSince(start) >= sustainedHighDuration {
                let readyToFire = lastCalmTriggerAt.map { now.timeIntervalSince($0) >= cooldown } ?? true
                if readyToFire {
                    lastCalmTriggerAt = now
                    highStreakStart = nil  // must re-accumulate before firing again
                    return .calmScene
                }
            }
        } else {
            highStreakStart = nil
        }

        if hasSettled {
            let readyToFire = lastCelebrateTriggerAt.map { now.timeIntervalSince($0) >= cooldown } ?? true
            if readyToFire {
                lastCelebrateTriggerAt = now
                return .celebrateScene
            }
        }

        return nil
    }
}
