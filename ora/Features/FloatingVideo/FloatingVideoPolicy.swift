import Foundation

/// Decides which video, if any, should float. Pure logic, so it can be tested without WebKit.
enum FloatingVideoPolicy {
    struct Rules: Equatable {
        /// Smaller videos are usually previews, ads, or decoration.
        var minimumWidth: Double = 200
        var minimumHeight: Double = 120
        /// Share of the video that must be on screen for it to float on a tab switch.
        var minimumVisibleFraction: Double = 0.5

        static let standard = Rules()
    }

    enum ManualAction: Equatable {
        case float(candidateID: Int)
        case returnInline
        case noVideo
    }

    /// The video to float when the user leaves its tab. It has to be playing, audible, mostly
    /// visible, and big enough, which skips muted autoplay backgrounds and small previews.
    /// `FloatingVideoScript.enterAutomatic` applies the same rules inside the page.
    static func automaticCandidate(
        from candidates: [BrowserVideoCandidate],
        rules: Rules = .standard
    ) -> BrowserVideoCandidate? {
        guard !candidates.contains(where: \.isFloating) else { return nil }

        return candidates
            .filter { candidate in
                candidate.supportsFloating
                    && candidate.isPlaying
                    && !candidate.isMuted
                    && isLargeEnough(candidate, rules: rules)
                    && candidate.visibleFraction >= rules.minimumVisibleFraction
            }
            .max { visibleArea(of: $0) < visibleArea(of: $1) }
    }

    /// What the Pop Out Video command does. A floating video comes back to the page. Otherwise
    /// the command floats the largest visible video, preferring one that is playing. Muted or
    /// paused videos are allowed here because the user asked for it.
    static func manualAction(
        for candidates: [BrowserVideoCandidate],
        rules: Rules = .standard
    ) -> ManualAction {
        if candidates.contains(where: \.isFloating) {
            return .returnInline
        }

        let eligible = candidates.filter { candidate in
            candidate.supportsFloating
                && isLargeEnough(candidate, rules: rules)
                && candidate.visibleFraction > 0
        }
        let playing = eligible.filter(\.isPlaying)
        let pool = playing.isEmpty ? eligible : playing

        guard let best = pool.max(by: { visibleArea(of: $0) < visibleArea(of: $1) }) else {
            return .noVideo
        }
        return .float(candidateID: best.id)
    }

    static func isTabSwitch(from oldTabID: UUID?, to newTabID: UUID?) -> Bool {
        oldTabID != nil && oldTabID != newTabID
    }

    private static func isLargeEnough(_ candidate: BrowserVideoCandidate, rules: Rules) -> Bool {
        candidate.width >= rules.minimumWidth && candidate.height >= rules.minimumHeight
    }

    private static func visibleArea(of candidate: BrowserVideoCandidate) -> Double {
        candidate.width * candidate.height * candidate.visibleFraction
    }
}
