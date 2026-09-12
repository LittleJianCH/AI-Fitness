import ContractClient
import Foundation
import HTTPTypes
import OpenAPIRuntime
import XCTest
@testable import FitnessCore

final class APITests: XCTestCase {
    func testAuthenticatedRequestCarriesBearerWithoutBrowserCredentials() async throws {
        let transport = FixtureTransport { request, _, base in
            XCTAssertEqual(request.path, "/api/v1/me")
            XCTAssertEqual(base.absoluteString, "https://fitness.invalid")
            XCTAssertEqual(request.headerFields[.authorization], "Bearer synthetic-token")
            XCTAssertNil(request.headerFields[.cookie])
            XCTAssertNil(request.headerFields[.origin])
            return (HTTPResponse(status: .ok, headerFields: [.contentType: "application/json; charset=utf-8"]), HTTPBody(Data(Self.userJSON.utf8)))
        }
        let api = FitnessAPI(endpoint: try ServerEndpoint("https://fitness.invalid"), transport: transport)
        let user = try await api.currentUser(token: "synthetic-token")
        XCTAssertEqual(user.username, "alice")
    }

    func testLoginHasNoCredentialHeaderAndEncodesTheCanonicalBody() async throws {
        let transport = FixtureTransport { request, body, _ in
            XCTAssertEqual(request.path, "/api/v1/auth/native/login")
            XCTAssertNil(request.headerFields[.authorization])
            let data = try await Data(collecting: XCTUnwrap(body), upTo: 4096)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
            XCTAssertEqual(object, ["username": "alice", "password": "synthetic", "deviceName": "Test"])
            return (HTTPResponse(status: .unauthorized, headerFields: [.contentType: "application/json"]), HTTPBody(Data(Self.problemJSON.utf8)))
        }
        let api = FitnessAPI(endpoint: try ServerEndpoint("https://fitness.invalid"), transport: transport)
        do {
            _ = try await api.login(username: "alice", password: "synthetic", deviceName: "Test")
            XCTFail("Expected unauthorized")
        } catch let error as APIResponseError {
            XCTAssertEqual(error.status, 401)
            XCTAssertEqual(error.problem?.code, "unauthenticated")
        }
    }

    func testNonJSONErrorsKeepStatusAndDoNotExposeRawDiagnostics() async throws {
        let api = FitnessAPI(endpoint: try ServerEndpoint("https://fitness.invalid"), transport: FixtureTransport { _, _, _ in
            (HTTPResponse(status: .internalServerError), HTTPBody("sensitive upstream diagnostic"))
        })
        do {
            _ = try await api.currentUser(token: "synthetic")
            XCTFail("Expected failure")
        } catch let error as APIResponseError {
            XCTAssertEqual(error.status, 500)
            XCTAssertNil(error.problem)
            XCTAssertFalse(userFacingError(error).contains("sensitive"))
        }
    }

    #if os(macOS)
    func testRealURLSessionRefusesRedirects() async throws {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Support/redirect_server.py")
        process.arguments = [script.path]
        process.standardOutput = output
        try process.run()
        defer { process.terminate(); process.waitUntilExit() }
        var line = Data()
        while line.count < 10 {
            let byte = output.fileHandleForReading.readData(ofLength: 1)
            if byte.isEmpty || byte == Data([10]) { break }
            line.append(byte)
        }
        let port = try XCTUnwrap(Int(String(decoding: line, as: UTF8.self)))
        let api = FitnessAPI(endpoint: try ServerEndpoint("http://127.0.0.1:\(port)", allowLoopbackHTTP: true))
        do {
            _ = try await api.currentUser(token: "synthetic-redirect-probe")
            XCTFail("A credential-bearing request must not follow a redirect")
        } catch let error as APIResponseError { XCTAssertEqual(error.status, 307) }
    }
    #endif

    static let userJSON = #"{"createdAt":"2026-09-12T00:00:00Z","id":"00000000-0000-0000-0000-000000000001","username":"alice"}"#
    static let problemJSON = #"{"code":"unauthenticated","message":"Invalid credentials","requestId":"synthetic","fields":[]}"#
}

struct FixtureTransport: ClientTransport {
    let response: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    func send(_ request: HTTPRequest, body: HTTPBody?, baseURL: URL, operationID: String) async throws -> (HTTPResponse, HTTPBody?) {
        try await response(request, body, baseURL)
    }
}
