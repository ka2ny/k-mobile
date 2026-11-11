import XCTest

final class NavigationTests: XCTestCase {
    @MainActor
    func testDisconnectedRoutesAndPairingCancel() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.navigationBars["k-hole"].waitForExistence(timeout: 10))
        capture("Home", app)
        app.buttons["Connections"].tap()
        XCTAssertTrue(app.navigationBars["Connections"].waitForExistence(timeout: 3))
        app.buttons["connections.add"].tap()
        XCTAssertTrue(app.navigationBars["Make a connection"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Pair securely"].isEnabled)
        capture("Pairing-empty", app)
        app.buttons["Cancel"].tap()
        app.buttons["Done"].tap()
        for title in ["k-chain", "Controls", "Assistant", "Activity"] {
            app.tabBars.buttons[title].tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 3))
            capture(title, app)
        }
        app.tabBars.buttons["Controls"].tap()
        XCTAssertTrue(app.staticTexts["Your companion is out of reach"].exists)
        XCTAssertFalse(app.buttons["Lock computer"].exists)
    }

    @MainActor
    func testDarkAppearanceRoutes() throws {
        let app = XCUIApplication()
        // Set the real app preference through UserDefaults' launch-argument domain.
        app.launchArguments = ["-appearance.mode", "dark"]
        app.launch()
        XCTAssertTrue(app.navigationBars["k-hole"].waitForExistence(timeout: 10))
        capture("Dark-Home", app)
        for title in ["k-chain", "Controls", "Assistant", "Activity"] {
            app.tabBars.buttons[title].tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 3))
            capture("Dark-" + title, app)
        }
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["appearance.mode"].firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any)["appearance.accent"].firstMatch.exists)
        capture("Dark-Settings", app)
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) { XCUIApplication().launch() }
    }

    @MainActor
    private func capture(_ title: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = title
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
