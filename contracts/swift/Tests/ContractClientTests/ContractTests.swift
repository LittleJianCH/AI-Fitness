@testable import ContractClient
import Foundation
import HTTPTypes
import OpenAPIRuntime
import XCTest

final class ContractTests: XCTestCase {
    func testHighPrecisionFractionalTimestamps() throws {
        let transcoder = FitnessDateTranscoder()
        let whole = try transcoder.decode("2024-01-01T10:00:32Z")
        for digits in ["3", "333333", "333333333333", "666666666667", "123456789012", "999999999999"] {
            let expected = try XCTUnwrap(Double("0." + digits))
            for (clock, zone) in [("10:00:32", "Z"), ("18:00:32", "+08:00"), ("05:00:32", "-05:00")] {
                let decoded = try transcoder.decode("2024-01-01T\(clock).\(digits)\(zone)")
                XCTAssertEqual(decoded.timeIntervalSince(whole), expected, accuracy: 0.000001)
            }
        }
        for invalid in ["invalid-date", "2024-01-01T10:00:32.Z", "2024-01-01T10:00:32.xyzZ"] {
            XCTAssertThrowsError(try transcoder.decode(invalid))
        }
    }

    func testGeneratedClientDecodesPicosecondTimestamps() async throws {
        let bytes = try fixtureData("export-response")
        let response = Data(String(decoding: bytes, as: UTF8.self)
            .replacingOccurrences(of: "2026-09-05T05:55:32.125Z", with: "2026-09-05T05:55:32.333333333333Z").utf8)
        let client = makeFitnessClient(
            serverURL: try XCTUnwrap(URL(string: "https://fitness.invalid")),
            transport: FixtureTransport(response: response)
        )
        let exported = try await client.get_workouts_workoutId_exports_canonical(path: .init(workoutId: workoutID))
            .ok.body.application_json_charset_utf_hyphen_8
        let whole = try FitnessDateTranscoder().decode("2026-09-05T05:55:32Z")
        XCTAssertEqual(exported.exportedAt.timeIntervalSince(whole), 1.0 / 3, accuracy: 0.000001)
    }

    func testGeneratedClientDecodesServantResponses() async throws {
        let list = try fixtureClient("list-response")
        let page = try await list.get_workouts().ok.body.application_json_charset_utf_hyphen_8
        XCTAssertEqual(page.items.count, 2)
        XCTAssertEqual(page.items.first?.revision, "9007199254740993")
        XCTAssertNil(page.nextCursor)

        let detail = try fixtureClient("workout-response")
        let workout = try await detail.get_workouts_workoutId(path: .init(workoutId: workoutID))
            .ok.body.application_json_charset_utf_hyphen_8
        XCTAssertEqual(workout.workoutId, workoutID)

        let exported = try await exportFixture()
        XCTAssertEqual(exported.workouts.count, 2)
        XCTAssertEqual(exported.version, .canonicalV1)
        XCTAssertEqual(exported.exportedAt.timeIntervalSince1970.truncatingRemainder(dividingBy: 1), 0.125)

        let failure = try fixtureClient("error-response", status: .badRequest)
        let problem = try await failure.get_workouts().badRequest.body.application_json_charset_utf_hyphen_8
        XCTAssertEqual(problem.code, "invalid_query")
    }

    func testGeneratedClientPreservesFractionalRequestTimes() async throws {
        let exported = try await exportFixture()
        let date = exported.exportedAt
        let list = try fixtureClient("list-response") { request, _ in
            let path = try XCTUnwrap(request.path)
            let query = try XCTUnwrap(URLComponents(string: path)?.queryItems)
            XCTAssertEqual(query.first(where: { $0.name == "from" })?.value, "2026-09-05T05:55:32.125Z")
        }
        _ = try await list.get_workouts(query: .init(from: date))

        var workout = try XCTUnwrap(exported.workouts.first)
        workout.workoutObservation.observationRange.rangeStart = date
        let create = try fixtureClient("workout-response") { request, body in
            XCTAssertEqual(request.method, .post)
            XCTAssertEqual(request.path, "/api/v1/workouts")
            let bytes = try await Data(collecting: XCTUnwrap(body), upTo: 1_000_000)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
            let observation = try XCTUnwrap(json["observation"] as? [String: Any])
            let range = try XCTUnwrap(observation["observationRange"] as? [String: Any])
            XCTAssertEqual(range["rangeStart"] as? String, "2026-09-05T05:55:32.125Z")
        }
        _ = try await create.post_workouts(body: .application_json_charset_utf_hyphen_8(.init(
            observation: workout.workoutObservation,
            submissionId: workoutID,
            userData: workout.workoutUserData
        )))
    }

    func testGeneratedClientRejectsInvalidDates() async throws {
        let bytes = try fixtureData("export-response")
        let invalid = Data(String(decoding: bytes, as: UTF8.self)
            .replacingOccurrences(of: "2026-09-05T05:55:32.125Z", with: "invalid-date").utf8)
        let client = makeFitnessClient(
            serverURL: try XCTUnwrap(URL(string: "https://fitness.invalid")),
            transport: FixtureTransport(response: invalid)
        )
        do {
            _ = try await client.get_workouts_workoutId_exports_canonical(path: .init(workoutId: workoutID))
            XCTFail("Invalid dates must fail through the generated client")
        } catch let error as ClientError {
            guard case DecodingError.dataCorrupted = error.underlyingError else {
                return XCTFail("Expected a date decoding error, got \(error.underlyingError)")
            }
        }
    }
}

private let workoutID = "00000000-0000-0000-0000-000000000001"

private func fixtureData(_ name: String) throws -> Data {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
    return try Data(contentsOf: root.appendingPathComponent("backend/build/\(name).json"))
}

private func fixtureClient(
    _ name: String,
    status: HTTPResponse.Status = .ok,
    inspect: @escaping @Sendable (HTTPRequest, HTTPBody?) async throws -> Void = { _, _ in }
) throws -> Client {
    makeFitnessClient(
        serverURL: try XCTUnwrap(URL(string: "https://fitness.invalid")),
        transport: FixtureTransport(response: try fixtureData(name), status: status, inspect: inspect)
    )
}

private func exportFixture() async throws -> Components.Schemas.CanonicalExport {
    let client = try fixtureClient("export-response")
    return try await client.get_workouts_workoutId_exports_canonical(path: .init(workoutId: workoutID))
        .ok.body.application_json_charset_utf_hyphen_8
}

private struct FixtureTransport: ClientTransport {
    let response: Data
    var status: HTTPResponse.Status = .ok
    var inspect: @Sendable (HTTPRequest, HTTPBody?) async throws -> Void = { _, _ in }

    func send(_ request: HTTPRequest, body: HTTPBody?, baseURL: URL, operationID: String) async throws
        -> (HTTPResponse, HTTPBody?) {
        try await inspect(request, body)
        return (HTTPResponse(status: status, headerFields: [.contentType: "application/json;charset=utf-8"]), HTTPBody(response))
    }
}
