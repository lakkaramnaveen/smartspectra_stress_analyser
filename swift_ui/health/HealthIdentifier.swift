import Foundation

/// String identifiers matching HealthKit's own public constants exactly.
///
/// Reproduced here as plain strings because the `HealthKit` framework
/// itself cannot be imported in this target — HealthKit is restricted to
/// iOS, watchOS, and visionOS, and this is a native macOS app. There is
/// no conditional-compilation path around that; it's not available at
/// all, not merely limited.
///
/// Kept in one place so a future companion iOS/watchOS app — where
/// `import HealthKit` *does* compile — can map straight from these
/// strings to `HKQuantityTypeIdentifier` / `HKCategoryTypeIdentifier`
/// cases without re-deriving the spelling. Each value below is the exact
/// `.rawValue` HealthKit itself would produce.
enum HealthIdentifier {
    /// `HKQuantityTypeIdentifier.heartRate.rawValue`
    static let heartRate = "HKQuantityTypeIdentifierHeartRate"

    /// `HKQuantityTypeIdentifier.respiratoryRate.rawValue`
    static let respiratoryRate = "HKQuantityTypeIdentifierRespiratoryRate"

    /// `HKCategoryTypeIdentifier.mindfulSession.rawValue` — an interval
    /// sample (start/end only, no numeric value), which is why
    /// `MindfulInterval` below carries no measurement field.
    static let mindfulSession = "HKCategoryTypeIdentifierMindfulSession"

    /// `HKUnit.count().unitDivided(by: .minute())`, spelled the way
    /// HealthKit's own `unitString` renders it. Both heart rate and
    /// respiratory rate use this unit.
    static let countPerMinuteUnit = "count/min"
}
