import XCTest

/// End-to-end checks that run on a disposable macOS runner. See
/// `.agents/skills/test-ora-macos/SKILL.md` for how agents run them.
final class OraSmokeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchShowsBrowserWindow() {
        let app = launchOra()

        attachScreenshot(of: app, named: "launch")
    }

    @MainActor
    func testOpensFixturePage() throws {
        let fixture = try fixtureURL("basic.html")
        let app = launchOra()

        app.open(fixture)

        let marker = app.webViews.staticTexts["Ora agent fixture loaded"]
        XCTAssertTrue(marker.waitForExistence(timeout: 30), "Fixture page never rendered its marker text")
        attachScreenshot(of: app, named: "fixture-basic")
    }

    // MARK: - Helpers

    @MainActor
    private func launchOra() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 30), "Ora never showed a window")
        return app
    }

    /// Fixture pages are served by `scripts/agent-test/run.sh`, which passes the base URL
    /// through `TEST_RUNNER_ORA_FIXTURE_BASE_URL`.
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
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
