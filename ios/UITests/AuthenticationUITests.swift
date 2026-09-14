import XCTest

final class AuthenticationUITests: XCTestCase {
    @MainActor
    func testDenseWorkoutChartsRemainUsable() throws {
        guard let server = ProcessInfo.processInfo.environment["FITNESS_TEST_SERVER"],
              server.hasPrefix("http://127.0.0.1:") else {
            throw XCTSkip("Run through the isolated iOS integration harness.")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-serverOrigin", server]
        app.launch()
        let username = app.textFields["username"]
        XCTAssertTrue(username.waitForExistence(timeout: 15))
        username.tap()
        username.typeText("ios_fixture_user")
        app.secureTextFields["password"].tap()
        app.secureTextFields["password"].typeText("synthetic ios fixture password")
        app.buttons["login"].tap()
        let dense = app.staticTexts["Synthetic dense cycling"]
        XCTAssertTrue(dense.waitForExistence(timeout: 15))
        dense.tap()
        XCTAssertTrue(app.staticTexts["workoutTitle"].waitForExistence(timeout: 15))
        let reduced = app.staticTexts["概览保留分段峰谷，原始采样完整保留。"].firstMatch
        reveal(reduced, in: app)
        let refresh = app.buttons["刷新训练"]
        reveal(refresh, in: app)
        refresh.tap()
        let power = app.staticTexts["powerCurveSelected"]
        reveal(power, in: app)
        XCTAssertTrue(power.label.contains("W"))
        capture(app, name: "Dense workout power curve")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(dense.waitForExistence(timeout: 10))
        app.tabBars.buttons["账号"].tap()
        XCTAssertTrue(app.buttons["logout"].waitForExistence(timeout: 10))
        app.buttons["logout"].tap()
        XCTAssertTrue(username.waitForExistence(timeout: 10))
    }

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
        XCTAssertTrue(app.images["跑步"].exists)
        XCTAssertTrue(app.images["骑行"].exists)
        capture(app, name: "Workouts")
        app.segmentedControls.buttons["跑步"].tap()
        XCTAssertTrue(app.staticTexts["Synthetic running"].waitForExistence(timeout: 10))
        let cyclingAbsent = NSPredicate(format: "exists == false")
        expectation(for: cyclingAbsent, evaluatedWith: app.staticTexts["Synthetic cycling"])
        waitForExpectations(timeout: 10)
        app.staticTexts["Synthetic running"].tap()
        XCTAssertTrue(app.staticTexts["workoutTitle"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["workoutTitle"].label, "Synthetic running")
        XCTAssertTrue(app.staticTexts["记录摘要"].exists)
        let averageHeartRate = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "平均心率")).firstMatch
        XCTAssertFalse(averageHeartRate.exists)
        app.disclosureTriangles["更多摘要指标"].tap()
        XCTAssertTrue(averageHeartRate.waitForExistence(timeout: 5))
        app.disclosureTriangles["更多摘要指标"].tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: averageHeartRate)
        waitForExpectations(timeout: 5)
        capture(app, name: "Workout detail")
        // The isolated harness injects a stale curve once. Refreshing removes
        // the child section; its cancellation must not cancel the detail load.
        let refreshWorkout = app.buttons["刷新训练"]
        reveal(refreshWorkout, in: app)
        refreshWorkout.tap()
        XCTAssertTrue(app.staticTexts["workoutTitle"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(app.staticTexts["workoutTitle"].label, "Synthetic running")
        reveal(app.staticTexts["powerCurveSelected"], in: app)
        XCTAssertTrue(app.staticTexts["powerCurveSelected"].label.contains("200"))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["Synthetic running"].waitForExistence(timeout: 10))
        app.staticTexts["Synthetic running"].tap()
        XCTAssertTrue(app.buttons["openHealthExport"].waitForExistence(timeout: 10))
        app.buttons["openHealthExport"].tap()
        XCTAssertTrue(app.navigationBars["导出到 Apple 健康"].waitForExistence(timeout: 10))
        capture(app, name: "Health export")
        reveal(app.buttons["confirmHealthExport"], in: app)
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
        XCTAssertTrue(app.staticTexts["从苹果健康导入 AI Fitness"].exists)
        capture(app, name: "Apple Health")
        reveal(app.buttons["readHealthWorkouts"], in: app)
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
        XCTAssertTrue(app.navigationBars["导出到 Apple 健康"].waitForExistence(timeout: 10))
        reveal(app.buttons["confirmHealthExport"], in: app)
        app.buttons["confirmHealthExport"].tap()
        app.buttons["确认写入"].tap()
        XCTAssertTrue(app.staticTexts["Apple 健康写入与后端回执均已确认。"].waitForExistence(timeout: 10))
        app.buttons["closeHealthExport"].tap()
        let heartRateChart = app.otherElements["metric-heartRate"].firstMatch
        XCTAssertTrue(heartRateChart.waitForExistence(timeout: 10))
        heartRateChart.tap()
        XCTAssertTrue(heartRateChart.isHittable)
        capture(app, name: "Heart rate")
        let power = app.staticTexts["powerCurveSelected"]
        reveal(power, in: app)
        XCTAssertTrue(power.label.contains("200"), power.label)
        capture(app, name: "Power curve")
        let duration = app.buttons["powerCurveDuration"]
        reveal(duration, in: app)
        duration.tap()
        app.buttons["0:00:05"].tap()
        XCTAssertTrue(power.label.contains("0:00:05"), power.label)
        app.tabBars.buttons["账号"].tap()
        XCTAssertTrue(app.buttons["logout"].waitForExistence(timeout: 15))
        app.buttons["logout"].tap()
        XCTAssertTrue(username.waitForExistence(timeout: 10))
        app.terminate()
        app.launch()
        XCTAssertTrue(username.waitForExistence(timeout: 10))
        capture(app, name: "Login")
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        // Grouped forms create rows as they enter the viewport. Larger text can
        // place the action several screens below its introductory content.
        for _ in 0..<8 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable, app.debugDescription)
    }

    @MainActor
    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
