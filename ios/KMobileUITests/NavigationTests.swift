import XCTest

final class NavigationTests: XCTestCase {
    @MainActor
    func testDisconnectedRoutesAndPairingCancel() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.navigationBars["Computer"].waitForExistence(timeout: 10))
        capture("Computer", app)
        app.buttons["Connections"].tap()
        XCTAssertTrue(app.navigationBars["Connections"].waitForExistence(timeout: 3))
        app.buttons["connections.add"].tap()
        XCTAssertTrue(app.navigationBars["Make a connection"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Pair securely"].isEnabled)
        capture("Pairing-empty", app)
        app.buttons["Cancel"].tap()
        app.buttons["Done"].tap()
        for title in ["Beam", "Agents", "Assistant", "k-chain"] {
            app.tabBars.buttons[title].tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 3))
            capture(title, app)
        }
        app.tabBars.buttons["Beam"].tap()
        XCTAssertTrue(app.buttons["Connect a computer"].exists)
        app.tabBars.buttons["Agents"].tap()
        XCTAssertTrue(app.buttons["Connect a computer"].exists)
        app.tabBars.buttons["k-chain"].tap()
        app.buttons["Pair your k-chain"].tap()
        XCTAssertTrue(app.navigationBars["Set up k-chain"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["accessory.discover"].exists)
        XCTAssertFalse(app.staticTexts["Bluetooth verified"].exists)
        capture("k-chain-Setup", app)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["k-chain"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testDarkAppearanceRoutes() throws {
        let app = XCUIApplication()
        // Set the real app preference through UserDefaults' launch-argument domain.
        app.launchArguments = ["-appearance.mode", "dark"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Computer"].waitForExistence(timeout: 10))
        capture("Dark-Computer", app)
        for title in ["Beam", "Agents", "Assistant", "k-chain"] {
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
    func testAccessorySetupAtAccessibilityTextSize() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
                               "-accessibility.reduceMotion", "YES"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Computer"].waitForExistence(timeout: 10))
        app.tabBars.buttons["k-chain"].tap()
        let pair = app.buttons["Pair your k-chain"]
        for _ in 0..<6 where !pair.isHittable { app.swipeUp() }
        pair.tap()
        XCTAssertTrue(app.navigationBars["Set up k-chain"].waitForExistence(timeout: 3))
        let discover = app.buttons["accessory.discover"]
        for _ in 0..<8 where !discover.isHittable { app.swipeUp() }
        XCTAssertTrue(discover.isHittable)
        capture("k-chain-Setup-Large-Text", app)
        app.buttons["Cancel"].tap()
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
