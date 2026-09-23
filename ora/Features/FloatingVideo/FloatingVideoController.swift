import Foundation
import os

private let logger = Logger(subsystem: "com.orabrowser.ora", category: "FloatingVideo")

/// Floats a playing video when the user leaves its tab or Space, and returns it to the page when
/// they come back. Also runs the Pop Out Video command.
///
/// All state is in memory. Nothing about floating video is saved, in private windows or otherwise.
@MainActor
final class FloatingVideoController {
    enum ToggleResult: Equatable {
        case floated
        case returnedInline
        case noVideo
        case failed
    }

    private let rules: FloatingVideoPolicy.Rules
    private var activeTabID: UUID?
    private var suppressionDepth = 0

    init(rules: FloatingVideoPolicy.Rules = .standard) {
        self.rules = rules
    }

    private var isAutomaticFloatingEnabled: Bool {
        suppressionDepth == 0 && SettingsStore.shared.autoPiPEnabled
    }

    /// Call whenever the active tab changes, including Space switches and closing the last tab.
    func activeTabDidChange(from oldTab: Tab?, to newTab: Tab?) {
        let oldTabID = oldTab?.id
        let newTabID = newTab?.id
        guard oldTabID != newTabID else { return }
        activeTabID = newTabID

        // A video that floated because the user left this tab goes back inline.
        // Videos the user popped out by hand stay where they are.
        newTab?.browserPage?.exitFloatingVideo(automaticOnly: true)

        guard FloatingVideoPolicy.isTabSwitch(from: oldTabID, to: newTabID),
              isAutomaticFloatingEnabled,
              let oldTabID,
              let page = oldTab?.browserPage
        else { return }

        page.enterFloatingVideoAutomatically(
            minimumWidth: rules.minimumWidth,
            minimumHeight: rules.minimumHeight,
            minimumVisibleFraction: rules.minimumVisibleFraction
        ) { [weak self, weak page] floated in
            guard floated, let self, let page else { return }
            // The user came back before the video finished floating.
            if self.activeTabID == oldTabID {
                page.exitFloatingVideo(automaticOnly: true)
            }
        }
    }

    /// Runs `body` without floating the tab being left, for example when that tab is closing.
    func withoutAutomaticFloating(_ body: () -> Void) {
        suppressionDepth += 1
        defer { suppressionDepth -= 1 }
        body()
    }

    /// Pops the main video of `tab` out, or returns a floating one to the page.
    func toggleFloatingVideo(in tab: Tab, completion: @escaping (ToggleResult) -> Void) {
        guard let page = tab.browserPage else {
            completion(.noVideo)
            return
        }

        page.floatingVideoCandidates { [rules = self.rules, weak page] candidates in
            guard let page else {
                completion(.failed)
                return
            }

            switch FloatingVideoPolicy.manualAction(for: candidates, rules: rules) {
            case let .float(candidateID):
                page.enterFloatingVideo(candidateID: candidateID, origin: .manual) { floated in
                    completion(floated ? .floated : .failed)
                }
            case .returnInline:
                page.exitFloatingVideo(automaticOnly: false) { returned in
                    completion(returned ? .returnedInline : .failed)
                }
            case .noVideo:
                logger.debug("No video to pop out among \(candidates.count) candidates")
                completion(.noVideo)
            }
        }
    }
}
