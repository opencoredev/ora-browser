import XCTest

/// Floating video (picture in picture) on tab switch and through the Pop Out Video command.
/// Uses `scripts/agent-test/fixtures/floating-video.html`, which reports its own state as text.
final class FloatingVideoUITests: XCTestCase {
    private let fixtureTitle = "Ora Floating Video Fixture"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testVideoFloatsOnTabSwitchAndReturnsInline() throws {
        let videoPage = try fixtureURL("floating-video.html")
        let otherPage = try fixtureURL("basic.html")
        let app = launchOra()

        app.open(videoPage)
        let playButton = app.webViews.buttons["Play video"]
        XCTAssertTrue(playButton.waitForExistence(timeout: 30), "Video fixture never rendered")
        playButton.click()
        let playing = app.webViews.staticTexts["Video is playing"]
        let startedPlaying = playing.waitForExistence(timeout: 15)
        attachScreenshot(of: app, named: "1-playing-inline")
        XCTAssertTrue(startedPlaying, "Fixture video never started playing")

        // Leaving the tab should float the video.
        app.open(otherPage)
        let marker = app.webViews.staticTexts["Ora agent fixture loaded"]
        XCTAssertTrue(marker.waitForExistence(timeout: 30), "Second tab never rendered")
        sleep(2)
        attachScreenshot(named: "2-other-tab-screen")

        // Coming back should return it to the page.
        selectVideoTab(in: app)
        let floatedOnce = app.webViews.staticTexts["Floated 1 time"].waitForExistence(timeout: 15)
        let inline = app.webViews.staticTexts["Video is inline"].waitForExistence(timeout: 15)
        attachScreenshot(named: "3-back-on-video-tab-screen")
        XCTAssertTrue(floatedOnce, "Video did not float when its tab was left")
        XCTAssertTrue(inline, "Video did not return inline when its tab came back")
    }

    @MainActor
    func testPopOutVideoCommandTogglesFloating() throws {
        let videoPage = try fixtureURL("floating-video.html")
        let app = launchOra()

        app.open(videoPage)
        let playButton = app.webViews.buttons["Play video"]
        XCTAssertTrue(playButton.waitForExistence(timeout: 30), "Video fixture never rendered")
        playButton.click()
        XCTAssertTrue(
            app.webViews.staticTexts["Video is playing"].waitForExistence(timeout: 15),
            "Fixture video never started playing"
        )

        app.typeKey("p", modifierFlags: [.command, .option])
        let floating = app.webViews.staticTexts["Video is floating"].waitForExistence(timeout: 15)
        attachScreenshot(named: "1-popped-out-screen")
        XCTAssertTrue(floating, "Pop Out Video did not float the video")

        app.typeKey("p", modifierFlags: [.command, .option])
        let inline = app.webViews.staticTexts["Video is inline"].waitForExistence(timeout: 15)
        attachScreenshot(of: app, named: "2-returned-inline")
        XCTAssertTrue(inline, "Pop Out Video did not return the video to the page")
    }

    // MARK: - Helpers

    @MainActor
    private func launchOra() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 30), "Ora never showed a window")
        return app
    }

    /// Clicks the video tab in the sidebar, or falls back to Command-2. Tabs opened later sort
    /// first, so on a fresh profile the video tab is second.
    @MainActor
    private func selectVideoTab(in app: XCUIApplication) {
        let sidebarItem = app.staticTexts.matching(identifier: fixtureTitle).firstMatch
        if sidebarItem.exists, sidebarItem.isHittable {
            sidebarItem.click()
        } else {
            app.typeKey("2", modifierFlags: .command)
        }
    }

    private func fixtureURL(_ path: String) throws -> URL {
        guard let base = ProcessInfo.processInfo.environment["ORA_FIXTURE_BASE_URL"],
              let url = URL(string: path, relativeTo: URL(string: base))
        else {
            throw XCTSkip("ORA_FIXTURE_BASE_URL is not set; run through scripts/agent-test/run.sh")
        }
        return url.absoluteURL
    }

    @MainActor
    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        add(screenshotAttachment(app.screenshot(), named: name))
    }

    /// The floating window lives outside Ora's window, so capture the whole screen.
    @MainActor
    private func attachScreenshot(named name: String) {
        add(screenshotAttachment(XCUIScreen.main.screenshot(), named: name))
    }

    private func screenshotAttachment(_ screenshot: XCUIScreenshot, named name: String) -> XCTAttachment {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        return attachment
    }
}
