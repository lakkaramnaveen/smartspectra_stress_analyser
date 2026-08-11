import Foundation

/// Correlation statistics used by the insights engine.
///
/// Pure, dependency-free, and separated from any stress-domain meaning so
/// the numerical behaviour can be tested against textbook inputs — same
/// rationale as keeping `LinearFit` out of `StressTrendAnalyzer`.
enum CorrelationAnalyzer {

    // MARK: - Pearson

    /// Pearson product-moment correlation, in -1...1.
    ///
    /// Returns `nil` when undefined: mismatched lengths, fewer than three
    /// pairs, or either series being perfectly flat (zero variance means
    /// there is nothing to correlate, not a correlation of zero).
    static func pearson(_ xs: [Double], _ ys: [Double]) -> Double? {
        guard xs.count == ys.count, xs.count >= 3 else { return nil }

        let n = Double(xs.count)
        let meanX = xs.reduce(0, +) / n
        let meanY = ys.reduce(0, +) / n

        var covariance = 0.0
        var varianceX = 0.0
        var varianceY = 0.0

        for (x, y) in zip(xs, ys) {
            let dx = x - meanX
            let dy = y - meanY
            covariance += dx * dy
            varianceX += dx * dx
            varianceY += dy * dy
        }

        guard varianceX > 0, varianceY > 0 else { return nil }
        return covariance / (varianceX * varianceY).squareRoot()
    }

    // MARK: - Lead / Lag

    struct LeadLagResult: Sendable {
        /// How many samples the leading series moves ahead of the other.
        /// Positive means `leading` precedes `following`.
        let lagSamples: Int
        /// Correlation strength at that lag.
        let correlation: Double
    }

    /// Finds the lag at which `leading` best predicts `following`.
    ///
    /// Scans lags 0...`maxLagSamples`, correlating `leading[i]` against
    /// `following[i + lag]`, and returns the strongest positive result.
    ///
    /// Worth being clear about what this can and can't show: a lead-lag
    /// correlation says two signals tend to move in a consistent temporal
    /// order. It does not establish that one causes the other — both may
    /// follow a third thing. The insight copy built on this is worded as
    /// "tends to move before," never "causes."
    static func bestLead(
        leading: [Double],
        following: [Double],
        maxLagSamples: Int
    ) -> LeadLagResult? {
        guard leading.count == following.count,
              leading.count > maxLagSamples + 3,
              maxLagSamples > 0 else { return nil }

        var best: LeadLagResult?

        for lag in 0...maxLagSamples {
            let leadSlice = Array(leading.dropLast(lag))
            let followSlice = Array(following.dropFirst(lag))

            guard let r = pearson(leadSlice, followSlice) else { continue }

            if best == nil || r > best!.correlation {
                best = LeadLagResult(lagSamples: lag, correlation: r)
            }
        }

        return best
    }

    // MARK: - Descriptive helpers

    /// Plain-language strength band for a correlation coefficient, using
    /// conventional social-science thresholds. Used only for wording —
    /// the numeric value is always shown alongside it.
    static func strengthLabel(for r: Double) -> String {
        switch abs(r) {
        case ..<0.2: return "little"
        case ..<0.4: return "a weak"
        case ..<0.6: return "a moderate"
        case ..<0.8: return "a strong"
        default: return "a very strong"
        }
    }
}
