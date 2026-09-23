import Foundation
import os

private let logger = Logger(subsystem: "com.orabrowser.ora", category: "FloatingVideo")

/// Picture in picture for `<video>` elements in the main frame.
/// Requires `FloatingVideoScript.userScript` in the page configuration.
extension BrowserPage {
    func floatingVideoCandidates(completion: @escaping ([BrowserVideoCandidate]) -> Void) {
        callAsyncJavaScript(FloatingVideoScript.candidatesCall, world: .isolated) { result in
            switch result {
            case let .success(value):
                guard let json = value as? String, let data = json.data(using: .utf8) else {
                    completion([])
                    return
                }
                do {
                    completion(try JSONDecoder().decode([BrowserVideoCandidate].self, from: data))
                } catch {
                    logger.error("Could not decode video candidates: \(error.localizedDescription)")
                    completion([])
                }
            case let .failure(error):
                logger.debug("Could not read video candidates: \(error.localizedDescription)")
                completion([])
            }
        }
    }

    /// Calls `completion` with `true` when the video is floating.
    func enterFloatingVideo(
        candidateID: Int,
        origin: BrowserFloatingVideoOrigin,
        completion: ((Bool) -> Void)? = nil
    ) {
        callAsyncJavaScript(
            FloatingVideoScript.enterCall,
            arguments: ["id": candidateID, "origin": origin.rawValue],
            world: .isolated
        ) { result in
            let outcome = Self.floatingVideoOutcome(result)
            if outcome != "floating" {
                let originName = origin.rawValue
                logger.info("Video did not float (\(originName, privacy: .public)): \(outcome, privacy: .public)")
            }
            completion?(outcome == "floating")
        }
    }

    /// Picks the largest playing, audible, visible video that meets the size limits and floats it,
    /// all in one call. Calls `completion` with `true` when a video started floating.
    func enterFloatingVideoAutomatically(
        minimumWidth: Double,
        minimumHeight: Double,
        minimumVisibleFraction: Double,
        completion: ((Bool) -> Void)? = nil
    ) {
        callAsyncJavaScript(
            FloatingVideoScript.enterAutomaticCall,
            arguments: [
                "minWidth": minimumWidth,
                "minHeight": minimumHeight,
                "minVisibleFraction": minimumVisibleFraction
            ],
            world: .isolated
        ) { result in
            let outcome = Self.floatingVideoOutcome(result)
            if outcome.hasPrefix("failed") {
                logger.info("Video did not float automatically: \(outcome, privacy: .public)")
            }
            completion?(outcome == "floating")
        }
    }

    /// Returns the floating video to the page. With `automaticOnly`, a video the user floated
    /// by hand stays floating. Calls `completion` with `true` when no video is floating.
    func exitFloatingVideo(automaticOnly: Bool, completion: ((Bool) -> Void)? = nil) {
        callAsyncJavaScript(
            FloatingVideoScript.exitCall,
            arguments: ["automaticOnly": automaticOnly],
            world: .isolated
        ) { result in
            let outcome = Self.floatingVideoOutcome(result)
            if outcome.hasPrefix("failed") {
                logger.info("Video did not return inline: \(outcome, privacy: .public)")
            }
            completion?(outcome == "inline")
        }
    }

    private static func floatingVideoOutcome(_ result: Result<Any?, Error>) -> String {
        switch result {
        case let .success(value):
            (value as? String) ?? "unavailable"
        case let .failure(error):
            "failed:\(error.localizedDescription)"
        }
    }
}
