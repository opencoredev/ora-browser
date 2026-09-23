import Foundation
@testable import Ora
import Testing

struct FloatingVideoPolicyTests {
    // MARK: - Automatic floating

    @Test func floatsPlayingAudibleVisibleVideo() {
        let video = candidate(id: 1)

        #expect(FloatingVideoPolicy.automaticCandidate(from: [video]) == video)
    }

    @Test func skipsMutedVideo() {
        #expect(FloatingVideoPolicy.automaticCandidate(from: [candidate(id: 1, isMuted: true)]) == nil)
    }

    @Test func skipsPausedVideo() {
        #expect(FloatingVideoPolicy.automaticCandidate(from: [candidate(id: 1, isPlaying: false)]) == nil)
    }

    @Test func skipsTinyVideo() {
        let narrow = candidate(id: 1, width: 160, height: 300)
        let short = candidate(id: 2, width: 640, height: 90)

        #expect(FloatingVideoPolicy.automaticCandidate(from: [narrow, short]) == nil)
    }

    @Test func skipsMostlyOffscreenVideo() {
        #expect(FloatingVideoPolicy.automaticCandidate(from: [candidate(id: 1, visibleFraction: 0.3)]) == nil)
    }

    @Test func skipsVideoThatCannotFloat() {
        #expect(FloatingVideoPolicy.automaticCandidate(from: [candidate(id: 1, supportsFloating: false)]) == nil)
    }

    @Test func picksLargestVisibleVideo() {
        let small = candidate(id: 1, width: 320, height: 180)
        let large = candidate(id: 2, width: 960, height: 540)
        let largeButHalfHidden = candidate(id: 3, width: 1000, height: 560, visibleFraction: 0.5)

        #expect(FloatingVideoPolicy.automaticCandidate(from: [small, large, largeButHalfHidden])?.id == 2)
    }

    @Test func leavesPageAloneWhenAVideoIsAlreadyFloating() {
        let floating = candidate(id: 1, isPlaying: false, isFloating: true)
        let playing = candidate(id: 2)

        #expect(FloatingVideoPolicy.automaticCandidate(from: [floating, playing]) == nil)
    }

    @Test func respectsCustomRules() {
        let rules = FloatingVideoPolicy.Rules(minimumWidth: 100, minimumHeight: 60, minimumVisibleFraction: 0.2)
        let video = candidate(id: 1, width: 160, height: 90, visibleFraction: 0.3)

        #expect(FloatingVideoPolicy.automaticCandidate(from: [video], rules: rules) == video)
    }

    // MARK: - Pop Out Video command

    @Test func manualReturnsFloatingVideoInline() {
        let candidates = [candidate(id: 1), candidate(id: 2, isFloating: true)]

        #expect(FloatingVideoPolicy.manualAction(for: candidates) == .returnInline)
    }

    @Test func manualFloatsMutedOrPausedVideo() {
        let paused = candidate(id: 1, isPlaying: false, isMuted: true)

        #expect(FloatingVideoPolicy.manualAction(for: [paused]) == .float(candidateID: 1))
    }

    @Test func manualPrefersPlayingVideoOverLargerPausedOne() {
        let largePaused = candidate(id: 1, width: 1280, height: 720, isPlaying: false)
        let smallPlaying = candidate(id: 2, width: 320, height: 180)

        #expect(FloatingVideoPolicy.manualAction(for: [largePaused, smallPlaying]) == .float(candidateID: 2))
    }

    @Test func manualSkipsTinyOffscreenAndUnsupportedVideos() {
        let candidates = [
            candidate(id: 1, width: 100, height: 60),
            candidate(id: 2, visibleFraction: 0),
            candidate(id: 3, supportsFloating: false)
        ]

        #expect(FloatingVideoPolicy.manualAction(for: candidates) == .noVideo)
        #expect(FloatingVideoPolicy.manualAction(for: []) == .noVideo)
    }

    // MARK: - Tab switches

    @Test func detectsTabSwitch() {
        let first = UUID()
        let second = UUID()

        #expect(FloatingVideoPolicy.isTabSwitch(from: first, to: second))
        #expect(FloatingVideoPolicy.isTabSwitch(from: first, to: nil))
        #expect(!FloatingVideoPolicy.isTabSwitch(from: first, to: first))
        #expect(!FloatingVideoPolicy.isTabSwitch(from: nil, to: second))
    }

    // MARK: - Page script contract

    @Test func decodesCandidatesFromPageScript() throws {
        let json = """
        [{"id":7,"width":480,"height":270,"visibleFraction":1,"isPlaying":true,"isMuted":false,
          "isFloating":false,"isFloatingAutomatically":false,"supportsFloating":true}]
        """
        let decoded = try JSONDecoder().decode([BrowserVideoCandidate].self, from: Data(json.utf8))

        #expect(decoded == [candidate(id: 7, width: 480, height: 270)])
    }

    // MARK: - Helpers

    private func candidate(
        id: Int,
        width: Double = 640,
        height: Double = 360,
        visibleFraction: Double = 1,
        isPlaying: Bool = true,
        isMuted: Bool = false,
        isFloating: Bool = false,
        supportsFloating: Bool = true
    ) -> BrowserVideoCandidate {
        BrowserVideoCandidate(
            id: id,
            width: width,
            height: height,
            visibleFraction: visibleFraction,
            isPlaying: isPlaying,
            isMuted: isMuted,
            isFloating: isFloating,
            isFloatingAutomatically: false,
            supportsFloating: supportsFloating
        )
    }
}
