import Foundation

/// Joins app-focus sessions against stress readings by timestamp overlap
/// and reports which apps' windows ran hotter or calmer than baseline.
///
/// Pure and UI-free — same shape as every other analyzer in this app.
/// Deliberately produces **association, not causation**. "Stress ran
/// higher while Mail was frontmost" is a real, checkable pattern in the
/// data; "Mail causes stress" is a claim about the world this data can't
/// support on its own — the person might open Mail *because* something
/// else already raised their stress, or a demanding morning might
/// produce both independently. The generated copy in `AppUsageView`
/// reflects this distinction throughout, not just here.
struct AppStressAnalyzer: Sendable {

    let minimumSessionsPerApp: Int
    let minimumTotalMinutesPerApp: Double

    init(minimumSessionsPerApp: Int = 3, minimumTotalMinutesPerApp: Double = 10) {
        self.minimumSessionsPerApp = minimumSessionsPerApp
        self.minimumTotalMinutesPerApp = minimumTotalMinutesPerApp
    }

    func associate(
        appSessions: [AppFocusSession],
        stressSamples: [(timestamp: Date, stressScore: Double)]
    ) -> [AppStressAssociation] {
        guard !appSessions.isEmpty, !stressSamples.isEmpty else { return [] }

        let overallAverage = stressSamples.map(\.stressScore).average

        var minutesByApp: [String: TimeInterval] = [:]
        var sessionCountByApp: [String: Int] = [:]
        var nameByApp: [String: String] = [:]

        for session in appSessions {
            minutesByApp[session.bundleID, default: 0] += session.duration / 60
            sessionCountByApp[session.bundleID, default: 0] += 1
            nameByApp[session.bundleID] = session.appName
        }

        var stressByApp: [String: [Double]] = [:]
        for sample in stressSamples {
            guard let matched = appSessions.first(where: {
                sample.timestamp >= $0.start && sample.timestamp <= $0.end
            }) else { continue }
            stressByApp[matched.bundleID, default: []].append(sample.stressScore)
        }

        return stressByApp.compactMap { bundleID, scores -> AppStressAssociation? in
            guard let sessionCount = sessionCountByApp[bundleID],
                  sessionCount >= minimumSessionsPerApp,
                  let minutes = minutesByApp[bundleID],
                  minutes >= minimumTotalMinutesPerApp,
                  let name = nameByApp[bundleID] else {
                return nil
            }

            let appAverage = scores.average

            return AppStressAssociation(
                bundleID: bundleID,
                appName: name,
                sessionCount: sessionCount,
                totalMinutes: minutes,
                averageStressDuringApp: appAverage,
                overallAverageStress: overallAverage,
                deltaPoints: appAverage - overallAverage,
                confidence: .forSampleCount(sessionCount)
            )
        }
        .sorted { $0.deltaPoints > $1.deltaPoints }
    }
}
