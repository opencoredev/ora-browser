//
//  oraUITestsLaunchTests.swift
//  oraUITests
//
//  Created by keni on 6/21/25.
//

import XCTest

final class OraUITestsLaunchTests: XCTestCase {
    override static var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 30))

        // Runs once per appearance, so the evidence includes light and dark launch screenshots.
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "launch-screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
