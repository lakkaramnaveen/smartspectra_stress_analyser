import Foundation

/// A user's own resting-vitals averages, captured via a short calibration
/// session and used to personalize `StressScoringConfig` instead of
/// scoring everyone against the same fixed absolute thresholds.
///
/// Resting EDA and breathing rate vary a lot person to person — thresholds
/// tuned for an "average" user can under-react for one person and
/// over-react for another. This is the "what does *this* person's calm
/// baseline look like" reference point that scoring gets rescaled around.
struct StressBaseline: Codable, Equatable {
    let edaRestingMean: Double
    let breathingRestingMean: Double
    let pulseRestingMean: Double
    let sampleCount: Int
    let calibratedAt: Date
}
