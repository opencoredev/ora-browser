import Foundation
import Testing
@testable import Ora

struct TabSleepPolicyTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)
    private let timeout: TimeInterval = 1_800

    private func candidate(
        _ id: UUID = UUID(),
        age: TimeInterval = 2_000,
        active: Bool = false,
        playing: Bool = false,
        capturing: Bool = false,
        dirty: Bool = false,
        ready: Bool = true
    ) -> TabSleepCandidate {
        TabSleepCandidate(
            id: id,
            lastAccessedAt: now.addingTimeInterval(-age),
            isActive: active,
            isPlayingMedia: playing,
            isCapturingMedia: capturing,
            hasUnsavedFormInput: dirty,
            isWebViewReady: ready
        )
    }

    @Test func excludesProtectedTabs() {
        let policy = TabSleepPolicy(enabled: true, idleTimeout: timeout)
        let protected = [
            candidate(active: true),
            candidate(playing: true),
            candidate(capturing: true),
            candidate(dirty: true),
            candidate(ready: false),
            candidate(age: 100)
        ]

        #expect(policy.candidatesToSleep(protected, now: now).isEmpty)
    }

    @Test func ordersEligibleTabsLeastRecentlyUsedFirst() {
        let policy = TabSleepPolicy(enabled: true, idleTimeout: timeout)
        let oldest = candidate(age: 10_000)
        let middle = candidate(age: 5_000)
        let newest = candidate(age: 2_000)

        let selected = policy.candidatesToSleep([newest, oldest, middle], now: now, limit: 2)

        #expect(selected.map(\.id) == [oldest.id, middle.id])
    }

    @Test func idleDeadlineAndToggleControlTimerEligibility() {
        let policy = TabSleepPolicy(enabled: true, idleTimeout: timeout)
        let lastAccess = now.addingTimeInterval(-timeout)
        #expect(policy.idleDeadline(for: lastAccess) == now)
        #expect(policy.isIdle(candidate(age: timeout), now: now))
        #expect(!TabSleepPolicy(enabled: false, idleTimeout: timeout).isIdle(candidate(), now: now))
    }

    @Test func wakeUsesCapturedURLBeforeSavedURL() throws {
        let captured = try #require(URL(string: "https://example.com/current"))
        let saved = try #require(URL(string: "https://example.com/pinned"))
        let original = try #require(URL(string: "https://example.com/original"))

        #expect(TabSleepPolicy.wakeURL(sleepingURL: captured, savedURL: saved, currentURL: original) == captured)
        #expect(TabSleepPolicy.wakeURL(sleepingURL: nil, savedURL: saved, currentURL: original) == saved)
    }

    @Test func restoreNavigationSuppressesHistoryOnlyWhileRestoring() {
        #expect(TabHistoryPolicy.shouldRecordHistory(isRestoringNavigation: true) == false)
        #expect(TabHistoryPolicy.shouldRecordHistory(isRestoringNavigation: false))
    }
}
