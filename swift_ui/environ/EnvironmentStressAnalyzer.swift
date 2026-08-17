import Foundation

/// Correlates lighting and noise readings against stress, using the same
/// tercile-comparison shape `SleepStressAnalyzer` already uses — "stress
/// during your dimmest third of readings vs. your brightest third,"
/// mirroring "stress after your least vs. most restful nights." One
/// established pattern, applied to a new dimension, rather than a third
/// slightly different way of saying the same kind of thing.
struct EnvironmentStressAnalyzer: Sendable {

    static let minimumSamples = 15
    static let minimumCoefficient = 0.25

    func associate(
        dimension: EnvironmentDimension,
        readings: [(timestamp: Date, value: Double)],
        stressSamples: [(timestamp: Date, stressScore: Double)]
    ) -> EnvironmentAssociation? {
        guard readings.count >= Self.minimumSamples, !stressSamples.isEmpty else { return nil }

        // Pair each reading with the nearest stress sample within a
        // reasonable window — readings and stress snapshots are two
        // independently-timed streams, not guaranteed to land on the
        // same instant.
        let pairs: [(value: Double, stress: Double)] = readings.compactMap { reading in
            guard let nearest = stressSamples.min(by: {
                abs($0.timestamp.timeIntervalSince(reading.timestamp))
                    < abs($1.timestamp.timeIntervalSince(reading.timestamp))
            }), abs(nearest.timestamp.timeIntervalSince(reading.timestamp)) <= 30 else {
                return nil
            }
            return (reading.value, nearest.stressScore)
        }

        guard pairs.count >= Self.minimumSamples else { return nil }

        let sortedByValue = pairs.sorted { $0.value < $1.value }
        let tercile = max(sortedByValue.count / 3, 1)

        let lowerThird = sortedByValue.prefix(tercile).map(\.stress).average
        let upperThird = sortedByValue.suffix(tercile).map(\.stress).average

        let coefficient = CorrelationAnalyzer.pearson(
            pairs.map(\.value),
            pairs.map(\.stress)
        )

        return EnvironmentAssociation(
            dimension: dimension,
            sampleCount: pairs.count,
            stressInLowerThird: lowerThird,
            stressInUpperThird: upperThird,
            coefficient: coefficient
        )
    }
}
