import XCTest

final class AuthenticationUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

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
        XCTAssertTrue(app.buttons["logout"].waitForExistence(timeout: 15))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["logout"].waitForExistence(timeout: 15))
        app.buttons["logout"].tap()
        XCTAssertTrue(username.waitForExistence(timeout: 10))
        app.terminate()
        app.launch()
        XCTAssertTrue(username.waitForExistence(timeout: 10))
    }
}
