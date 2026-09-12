import XCTest

final class AuthenticationUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testServerValidation() {
        let app = XCUIApplication()
        app.launchArguments = ["-serverOrigin", ""]
        app.launch()
        let origin = app.textFields["serverOrigin"]
        XCTAssertTrue(origin.waitForExistence(timeout: 10))
        origin.tap()
        origin.typeText("http://example.com")
        app.buttons["connectServer"].tap()
        XCTAssertTrue(app.staticTexts["后端需要使用 HTTPS；开发模式只允许本机地址使用 HTTP。"].exists)
    }

    @MainActor
    func testLoginRestoreAndLogoutAgainstBackend() throws {
        guard let server = ProcessInfo.processInfo.environment["FITNESS_TEST_SERVER"],
              server.hasPrefix("http://127.0.0.1:") else {
            throw XCTSkip("Run through the isolated iOS integration harness to supply its temporary server.")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-serverOrigin", server]
        app.launch()
        let username = app.textFields["username"]
        XCTAssertTrue(username.waitForExistence(timeout: 15))
        username.tap()
        username.typeText("ios_fixture_user")
        let password = app.secureTextFields["password"]
        password.tap()
        password.typeText("incorrect")
        app.buttons["login"].tap()
        XCTAssertTrue(app.staticTexts["sessionError"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["用户名或密码不正确。"].exists)
        password.tap()
        password.typeText("synthetic ios fixture password")
        app.buttons["login"].tap()
        XCTAssertTrue(app.tabBars.buttons["账号"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Synthetic cycling"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Synthetic running"].exists)
        app.segmentedControls.buttons["跑步"].tap()
        XCTAssertTrue(app.staticTexts["Synthetic running"].waitForExistence(timeout: 10))
        let cyclingAbsent = NSPredicate(format: "exists == false")
        expectation(for: cyclingAbsent, evaluatedWith: app.staticTexts["Synthetic cycling"])
        waitForExpectations(timeout: 10)
        app.staticTexts["Synthetic running"].tap()
        XCTAssertTrue(app.staticTexts["workoutTitle"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["workoutTitle"].label, "Synthetic running")
        XCTAssertTrue(app.staticTexts["记录摘要"].exists)
        app.buttons["openHealthExport"].tap()
        XCTAssertTrue(app.buttons["confirmHealthExport"].waitForExistence(timeout: 10))
        app.buttons["confirmHealthExport"].tap()
        app.buttons["确认写入"].tap()
        // The harness owns a fresh simulator containing only synthetic workouts.
        let allowAll = app.cells["UIA.Health.AuthSheet.AllCategoryButton"]
        if allowAll.waitForExistence(timeout: 10) { allowAll.tap() }
        let allow = app.buttons["UIA.Health.AuthSheet.DoneButton"]
        if allow.waitForExistence(timeout: 5) { allow.tap() }
        XCTAssertTrue(app.staticTexts["Apple 健康写入与后端回执均已确认。"].waitForExistence(timeout: 30), app.debugDescription)
        app.buttons["closeHealthExport"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["Synthetic running"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Synthetic cycling"].exists)
        app.tabBars.buttons["健康"].tap()
        XCTAssertTrue(app.buttons["readHealthWorkouts"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["从苹果健康导入 AI Fitness"].exists)
        app.tabBars.buttons["账号"].tap()
        XCTAssertTrue(app.buttons["logout"].waitForExistence(timeout: 15))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["账号"].waitForExistence(timeout: 15))
        app.segmentedControls.buttons["跑步"].tap()
        XCTAssertTrue(app.staticTexts["Synthetic running"].waitForExistence(timeout: 10))
        app.staticTexts["Synthetic running"].tap()
        XCTAssertTrue(app.buttons["openHealthExport"].waitForExistence(timeout: 10))
        app.buttons["openHealthExport"].tap()
        XCTAssertTrue(app.buttons["confirmHealthExport"].waitForExistence(timeout: 10))
        app.buttons["confirmHealthExport"].tap()
        app.buttons["确认写入"].tap()
        XCTAssertTrue(app.staticTexts["Apple 健康写入与后端回执均已确认。"].waitForExistence(timeout: 10))
        app.buttons["closeHealthExport"].tap()
        app.tabBars.buttons["账号"].tap()
        XCTAssertTrue(app.buttons["logout"].waitForExistence(timeout: 15))
        app.buttons["logout"].tap()
        XCTAssertTrue(username.waitForExistence(timeout: 10))
        app.terminate()
        app.launch()
        XCTAssertTrue(username.waitForExistence(timeout: 10))
    }
}
