import XCTest
@testable import FitnessCore

final class EndpointTests: XCTestCase {
    func testOriginsAreCanonicalAndCredentialsStayScoped() throws {
        let a = try ServerEndpoint("HTTPS://EXAMPLE.COM:443/")
        let b = try ServerEndpoint("https://example.com")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, try ServerEndpoint("https://example.com:8443"))
    }

    func testOnlyExplicitLoopbackDevelopmentHTTPIsAllowed() throws {
        XCTAssertThrowsError(try ServerEndpoint("http://localhost:8000"))
        XCTAssertNoThrow(try ServerEndpoint("http://127.0.0.1:8000", allowLoopbackHTTP: true))
        for value in ["http://example.com", "http://192.168.1.2", "https://u:p@example.com", "https://example.com/api/v1", "https://example.com?token=x", "https://example.com#x"] {
            XCTAssertThrowsError(try ServerEndpoint(value, allowLoopbackHTTP: true), value)
        }
    }
}
