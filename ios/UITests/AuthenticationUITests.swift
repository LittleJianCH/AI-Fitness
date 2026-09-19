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
        XCTAssertTrue(app.segmentedControls["sportFilter"].waitForExistence(timeout: 15))
        reveal(dense, in: app)
        dense.tap()
        XCTAssertTrue(app.staticTexts["workoutTitle"].waitForExistence(timeout: 15))
        let reduced = app.otherElements["metric-heartRate"].firstMatch
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
        openAccount(in: app)
        XCTAssertTrue(app.buttons["logout"].waitForExistence(timeout: 10))
        app.buttons["logout"].tap()
        XCTAssertTrue(username.waitForExistence(timeout: 10))
    }

    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testSettingsPersistBodyParametersAndEquipment() throws {
        guard let server = ProcessInfo.processInfo.environment["FITNESS_TEST_SERVER"], server.hasPrefix("http://127.0.0.1:") else {
            throw XCTSkip("Run through the isolated iOS integration harness.")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-serverOrigin", server]
        app.launch()
        // A prior failed UI scenario must not hide this scenario's coverage.
        if app.tabBars.buttons["设置"].waitForExistence(timeout: 2) {
            openAccount(in: app)
            app.buttons["logout"].tap()
        }
        let username = app.textFields["username"]
        XCTAssertTrue(username.waitForExistence(timeout: 15))
        username.tap()
        username.typeText("ios_fixture_user")
        app.secureTextFields["password"].tap()
        app.secureTextFields["password"].typeText("synthetic ios fixture password")
        app.buttons["login"].tap()
        XCTAssertTrue(app.tabBars.buttons["设置"].waitForExistence(timeout: 15))
        app.tabBars.buttons["设置"].tap()
        let body = app.buttons["bodySettings"]
        XCTAssertTrue(body.waitForExistence(timeout: 15))
        body.tap()
        app.buttons["editBodyParameters"].tap()
        let mass = app.textFields["bodyMass"]
        XCTAssertTrue(mass.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(mass.label, "体重 (kg)")
        capture(app, name: "Body parameter editor")
        mass.tap()
        mass.typeText("72.5")
        app.textFields["bodyHeight"].tap()
        app.textFields["bodyHeight"].typeText("178")
        let cyclingPower = app.textFields["cycling-watts"]
        reveal(cyclingPower, in: app)
        cyclingPower.tap()
        cyclingPower.typeText("240")
        app.buttons["saveBodyParameters"].tap()
        XCTAssertTrue(app.staticTexts["体重, 72.5 kg"].waitForExistence(timeout: 10))
        capture(app, name: "Personal body parameter history")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["equipmentSettings"].tap()
        app.buttons["addEquipment"].tap()
        app.textFields["equipmentName"].tap()
        app.textFields["equipmentName"].typeText("Synthetic UI bicycle")
        app.textFields["equipmentMass"].tap()
        app.textFields["equipmentMass"].typeText("8.4")
        capture(app, name: "Equipment editor")
        app.buttons["saveEquipment"].tap()
        XCTAssertTrue(app.buttons["Synthetic UI bicycle"].waitForExistence(timeout: 10))
        capture(app, name: "Equipment settings")
        app.terminate()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["设置"].waitForExistence(timeout: 15))
        app.tabBars.buttons["设置"].tap()
        XCTAssertTrue(body.waitForExistence(timeout: 15))
        body.tap()
        XCTAssertTrue(app.staticTexts["体重, 72.5 kg"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["身高, 178.0 cm"].exists)
        app.buttons["editBodyParameters"].tap()
        XCTAssertTrue(mass.waitForExistence(timeout: 10))
        XCTAssertEqual(mass.value as? String, "72.5")
        XCTAssertEqual(app.textFields["bodyHeight"].value as? String, "178")
        app.buttons["取消"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["equipmentSettings"].tap()
        XCTAssertTrue(app.buttons["Synthetic UI bicycle"].waitForExistence(timeout: 10))
        app.buttons["Synthetic UI bicycle"].tap()
        XCTAssertTrue(app.textFields["equipmentName"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.textFields["equipmentName"].value as? String, "Synthetic UI bicycle")
        XCTAssertEqual(app.textFields["equipmentMass"].value as? String, "8.4")
        app.buttons["取消"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.tabBars.buttons["运动"].tap()
        let fallback = app.staticTexts["Synthetic profile fallback cycling"]
        XCTAssertTrue(fallback.waitForExistence(timeout: 10))
        fallback.tap()
        let massUsed = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "使用的体重", "72.5 kg")).firstMatch
        reveal(massUsed, in: app)
        XCTAssertTrue(massUsed.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "使用的阈值功率", "240 W")).firstMatch.exists)
        capture(app, name: "Backend analysis uses persisted body profile")
        openAccount(in: app)
        app.buttons["logout"].tap()
        XCTAssertTrue(username.waitForExistence(timeout: 10))
    }

    @MainActor
    func testMetricAnalysisAndTrainingHistoryAgainstBackend() throws {
        guard let server = ProcessInfo.processInfo.environment["FITNESS_TEST_SERVER"], server.hasPrefix("http://127.0.0.1:") else {
            throw XCTSkip("Run through the isolated iOS integration harness.")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-serverOrigin", server]
        app.launch()
        // A prior failed UI scenario must not hide this scenario's coverage.
        if app.tabBars.buttons["设置"].waitForExistence(timeout: 2) {
            openAccount(in: app)
            app.buttons["logout"].tap()
        }
        let username = app.textFields["username"]
        XCTAssertTrue(username.waitForExistence(timeout: 15))
        username.tap()
        username.typeText("ios_fixture_user")
        app.secureTextFields["password"].tap()
        app.secureTextFields["password"].typeText("synthetic ios fixture password")
        app.buttons["login"].tap()
        let dense = app.staticTexts["Synthetic dense cycling"]
        XCTAssertTrue(app.segmentedControls["sportFilter"].waitForExistence(timeout: 15))
        reveal(dense, in: app)
        dense.tap()
        let details = app.buttons["metricAnalysis-heartRate"]
        reveal(details, in: app)
        details.tap()
        XCTAssertTrue(app.navigationBars["心率分析"].waitForExistence(timeout: 10))
        capture(app, name: "Metric analysis overview")
        app.buttons["comparisonMetric"].tap()
        app.buttons["功率"].tap()
        XCTAssertTrue(app.staticTexts["两张图共享横轴位置，各自保留原始单位。"].waitForExistence(timeout: 5))
        capture(app, name: "Metric comparison over time")
        app.segmentedControls["metricAxis"].buttons["距离"].tap()
        XCTAssertTrue(app.segmentedControls["metricAxis"].buttons["距离"].isSelected)
        capture(app, name: "Metric comparison over distance")
        reveal(app.staticTexts["分布"], in: app)
        capture(app, name: "Metric distribution")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let history = app.buttons["体能与疲劳趋势"]
        reveal(history, in: app)
        history.tap()
        XCTAssertTrue(app.navigationBars["体能与疲劳"].waitForExistence(timeout: 10))
        let calculate = app.buttons["calculateTrainingHistory"]
        reveal(calculate, in: app)
        calculate.tap()
        XCTAssertTrue(app.staticTexts["请选择零起点假设，或填写非负的初始 CTL 和 ATL。"].waitForExistence(timeout: 5))
        let initial = app.switches["assumeNoPriorLoad"]
        reveal(initial, in: app)
        initial.switches.firstMatch.tap()
        XCTAssertEqual(initial.value as? String, "1")
        reveal(calculate, in: app)
        calculate.tap()
        XCTAssertTrue(app.staticTexts["训练趋势"].waitForExistence(timeout: 15), app.debugDescription)
        reveal(app.staticTexts["期末体能 CTL, 无数据"], in: app)
        capture(app, name: "Training history with unconfirmed completeness")
        reveal(app.staticTexts["每日负荷"], in: app)
        let unknownLoad = app.staticTexts["记录完整性、心率覆盖或个人参数不足，此日及后续趋势保留未知。"].firstMatch
        reveal(unknownLoad, in: app)
        XCTAssertTrue(unknownLoad.exists)
        capture(app, name: "Unknown daily training load")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let environment = app.staticTexts["Synthetic environment cycling"]
        reveal(app.segmentedControls["sportFilter"], in: app, searchingAbove: true)
        reveal(environment, in: app)
        environment.tap()
        let grade = app.buttons["metricAnalysis-grade"]
        reveal(grade, in: app)
        grade.tap()
        XCTAssertTrue(app.navigationBars["坡度分析"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "-8.2 %")).firstMatch.exists)
        capture(app, name: "Canonical grade analysis")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let temperature = app.buttons["metricAnalysis-temperature"]
        reveal(temperature, in: app)
        temperature.tap()
        XCTAssertTrue(app.navigationBars["环境温度分析"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "-3.5 °C")).firstMatch.exists)
        capture(app, name: "Canonical ambient temperature analysis")
        openAccount(in: app)
        XCTAssertTrue(app.buttons["logout"].waitForExistence(timeout: 10))
        app.buttons["logout"].tap()
        XCTAssertTrue(username.waitForExistence(timeout: 10))
    }

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
        XCTAssertTrue(app.tabBars.buttons["设置"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.segmentedControls["sportFilter"].waitForExistence(timeout: 15))
        reveal(app.staticTexts["Synthetic cycling"], in: app)
        XCTAssertTrue(app.images["骑行"].exists)
        reveal(app.segmentedControls["sportFilter"], in: app, searchingAbove: true)
        reveal(app.staticTexts["Synthetic running"], in: app)
        XCTAssertTrue(app.images["跑步"].exists)
        capture(app, name: "Workouts")
        reveal(app.segmentedControls["sportFilter"], in: app, searchingAbove: true)
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
        openAccount(in: app)
        XCTAssertTrue(app.buttons["logout"].waitForExistence(timeout: 15))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["设置"].waitForExistence(timeout: 15))
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
        openAccount(in: app)
        XCTAssertTrue(app.buttons["logout"].waitForExistence(timeout: 15))
        app.buttons["logout"].tap()
        XCTAssertTrue(username.waitForExistence(timeout: 10))
        app.terminate()
        app.launch()
        XCTAssertTrue(username.waitForExistence(timeout: 10))
        capture(app, name: "Login")
    }

    @MainActor
    private func openAccount(in app: XCUIApplication) {
        app.tabBars.buttons["设置"].tap()
        let account = app.buttons["账号与登录会话"]
        if account.waitForExistence(timeout: 5) { account.tap() }
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, searchingAbove: Bool = false) {
        // Grouped forms create rows as they enter the viewport. Larger text can
        // place the action several screens below its introductory content.
        for _ in 0..<20 {
            if element.exists {
                let top = app.navigationBars.firstMatch.exists ? app.navigationBars.firstMatch.frame.maxY : 0
                let bottom = app.tabBars.firstMatch.exists ? app.tabBars.firstMatch.frame.minY : app.frame.maxY
                if element.isHittable && element.frame.minY >= top && element.frame.maxY < bottom { return }
                // Short edge drags avoid oscillating past a row between the
                // navigation/tab bars, and do not select a chart underneath.
                let direction: CGFloat = element.frame.midY < (top + bottom) / 2 ? 1 : -1
                let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.5))
                let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.5 + direction * 0.2))
                start.press(forDuration: 0.05, thenDragTo: end)
                continue
            }
            if searchingAbove { app.swipeDown() } else { app.swipeUp() }
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

// Fault controls are enabled only by the disposable integration harness.
extension AuthenticationUITests {
    @MainActor
    func testRawMetricsAndPowerCurveSurviveAnalysisFailureAgainstBackend() async throws {
        guard let server = ProcessInfo.processInfo.environment["FITNESS_TEST_SERVER"], server.hasPrefix("http://127.0.0.1:") else {
            throw XCTSkip("Requires the disposable analysis-failure proxy.")
        }
        func setAnalysisFailure(_ enabled: Bool) async throws {
            let url = try XCTUnwrap(URL(string: server + "/__test/analysis-failure/" + (enabled ? "on" : "off")))
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            let (_, response) = try await URLSession.shared.data(for: request)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 204)
        }
        try await setAnalysisFailure(true)
        let app = XCUIApplication()
        app.launchArguments = ["-serverOrigin", server]
        app.launch()
        if app.tabBars.buttons["设置"].waitForExistence(timeout: 2) {
            openAccount(in: app)
            app.buttons["logout"].tap()
        }
        let username = app.textFields["username"]
        XCTAssertTrue(username.waitForExistence(timeout: 15))
        username.tap()
        username.typeText("ios_fixture_user")
        app.secureTextFields["password"].tap()
        app.secureTextFields["password"].typeText("synthetic ios fixture password")
        app.buttons["login"].tap()
        XCTAssertTrue(app.segmentedControls["sportFilter"].waitForExistence(timeout: 15))
        let dense = app.staticTexts["Synthetic dense cycling"]
        reveal(dense, in: app)
        dense.tap()
        let retry = app.buttons["重试分析"]
        reveal(retry, in: app)
        XCTAssertTrue(retry.exists)
        capture(app, name: "Derived analysis failure remains localized")
        let power = app.staticTexts["powerCurveSelected"]
        reveal(power, in: app, searchingAbove: true)
        XCTAssertTrue(power.label.contains("W"), power.label)
        capture(app, name: "Independent power curve during analysis failure")
        let raw = app.otherElements["metric-heartRate"].firstMatch
        reveal(raw, in: app, searchingAbove: true)
        let details = app.buttons["metricAnalysis-heartRate"]
        reveal(details, in: app)
        details.tap()
        XCTAssertTrue(app.navigationBars["心率分析"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["派生统计暂不可用，可返回运动详情重试分析。"].exists)
        XCTAssertFalse(app.staticTexts["分布"].exists)
        app.buttons["comparisonMetric"].tap()
        app.buttons["功率"].tap()
        XCTAssertTrue(app.staticTexts["两张图共享横轴位置，各自保留原始单位。"].waitForExistence(timeout: 5))
        app.segmentedControls["metricAxis"].buttons["距离"].tap()
        XCTAssertTrue(app.segmentedControls["metricAxis"].buttons["距离"].isSelected)
        capture(app, name: "Raw metric comparison without derived analysis")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        reveal(retry, in: app)
        try await setAnalysisFailure(false)
        retry.tap()
        let derived = app.staticTexts["心率与训练负荷"]
        reveal(derived, in: app)
        XCTAssertTrue(derived.exists)
        XCTAssertFalse(retry.exists)
        capture(app, name: "Derived analysis recovers after retry")
        openAccount(in: app)
        app.buttons["logout"].tap()
        XCTAssertTrue(username.waitForExistence(timeout: 10))
    }
}
