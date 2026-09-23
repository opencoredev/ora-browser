import Foundation

struct TabSleepCandidate: Identifiable, Equatable {
    let id: UUID
    let lastAccessedAt: Date?
    let isActive: Bool
    let isPlayingMedia: Bool
    let isCapturingMedia: Bool
    let hasUnsavedFormInput: Bool
    let isWebViewReady: Bool
}

struct TabSleepPolicy {
    let enabled: Bool
    let idleTimeout: TimeInterval

    func isIdle(_ candidate: TabSleepCandidate, now: Date) -> Bool {
        guard enabled, candidate.isWebViewReady,
              let lastAccessedAt = candidate.lastAccessedAt
        else { return false }
        return now.timeIntervalSince(lastAccessedAt) >= idleTimeout
    }

    func canSleep(_ candidate: TabSleepCandidate, now: Date) -> Bool {
        isIdle(candidate, now: now)
            && !candidate.isActive
            && !candidate.isPlayingMedia
            && !candidate.isCapturingMedia
            && !candidate.hasUnsavedFormInput
    }

    func candidatesToSleep(
        _ candidates: [TabSleepCandidate],
        now: Date,
        limit: Int? = nil
    ) -> [TabSleepCandidate] {
        let eligible = candidates
            .filter { canSleep($0, now: now) }
            .sorted { ($0.lastAccessedAt ?? .distantPast) < ($1.lastAccessedAt ?? .distantPast) }
        guard let limit else { return eligible }
        return Array(eligible.prefix(max(0, limit)))
    }

    func idleDeadline(for lastAccessedAt: Date) -> Date {
        lastAccessedAt.addingTimeInterval(idleTimeout)
    }

    static func wakeURL(sleepingURL: URL?, savedURL: URL?, currentURL: URL) -> URL {
        sleepingURL ?? savedURL ?? currentURL
    }
}

enum TabHistoryPolicy {
    static func shouldRecordHistory(isRestoringNavigation: Bool) -> Bool {
        !isRestoringNavigation
    }
}
