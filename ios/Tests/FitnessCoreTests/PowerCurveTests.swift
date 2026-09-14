import Foundation
import HTTPTypes
import OpenAPIRuntime
import XCTest
@testable import FitnessCore

final class PowerCurveTests: XCTestCase {
    func testGeneratedRequestAndBackendResponse() async throws {
        let curve = try await fixture()
        XCTAssertEqual(curve.inputRevision, "9007199254740993")
        let minute = try XCTUnwrap(curve.points.first { $0.durationSeconds == 60 }?.best)
        XCTAssertEqual(minute.averagePower, 200)
        XCTAssertEqual(minute.end.timeIntervalSince(minute.start), 60)
        XCTAssertNil(curve.points.first { $0.durationSeconds == 120 }?.best)
    }

    @MainActor
    func testFailureRetryAndRevisionMismatch() async throws {
        let curve = try await fixture()
        let service = ControlledCurve()
        let store = PowerCurveStore(service: service, session: await signedIn())
        let failed = Task { await store.load(id: curve.curveWorkoutId, revision: curve.inputRevision) }
        await service.waitForRequest()
        await service.respond(.failure(URLError(.notConnectedToInternet)))
        await failed.value
        XCTAssertNotNil(store.message)
        XCTAssertNil(store.curve)
        let retry = Task { await store.load(id: curve.curveWorkoutId, revision: curve.inputRevision) }
        await service.waitForRequest()
        await service.respond(.success(curve))
        await retry.value
        XCTAssertEqual(store.curve, curve)
        XCTAssertNil(store.message)
        let mismatch = Task { await store.load(id: curve.curveWorkoutId, revision: "2") }
        await service.waitForRequest()
        await service.respond(.success(curve))
        await mismatch.value
        XCTAssertNil(store.curve)
        XCTAssertTrue(store.needsWorkoutRefresh)
        XCTAssertFalse(store.isLoading)
    }

    @MainActor
    func testCancellationAndSessionChangesDiscardLateResults() async throws {
        let curve = try await fixture()
        let service = ControlledCurve()
        let session = await signedIn()
        let store = PowerCurveStore(service: service, session: session)
        let cancelled = Task { await store.load(id: curve.curveWorkoutId, revision: curve.inputRevision) }
        await service.waitForRequest()
        cancelled.cancel()
        await service.respond(.success(curve))
        await cancelled.value
        XCTAssertNil(store.curve)
        XCTAssertNil(store.message)
        let stale = Task { await store.load(id: curve.curveWorkoutId, revision: curve.inputRevision) }
        await service.waitForRequest()
        session.forgetSavedSession()
        await service.respond(.success(curve))
        await stale.value
        XCTAssertNil(store.curve)
        XCTAssertFalse(store.isLoading)
    }

    @MainActor
    func testUnauthorizedExpiresOnlyCurrentSession() async throws {
        let service = ControlledCurve()
        let session = await signedIn()
        let store = PowerCurveStore(service: service, session: session)
        let stale = Task { await store.load(id: "fixture", revision: "1") }
        await service.waitForRequest()
        session.forgetSavedSession()
        await session.login(username: "alice", password: "synthetic", deviceName: "Test")
        await service.respond(.failure(APIResponseError(status: 401, problem: nil, retryAfter: nil)))
        await stale.value
        XCTAssertNotNil(session.user)
        let current = Task { await store.load(id: "fixture", revision: "1") }
        await service.waitForRequest()
        await service.respond(.failure(APIResponseError(status: 401, problem: nil, retryAfter: nil)))
        await current.value
        XCTAssertNil(session.user)
    }

    @MainActor
    private func signedIn() async -> SessionStore {
        let session = SessionStore(service: TestAuth(), vault: MemoryVault())
        await session.login(username: "alice", password: "synthetic", deviceName: "Test")
        return session
    }

    private func fixture() async throws -> PowerCurve {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let bytes = try Data(contentsOf: root.appendingPathComponent("backend/build/power-curve-response.json"))
        let api = FitnessAPI(endpoint: try ServerEndpoint("https://fitness.invalid"), transport: FixtureTransport { request, _, _ in
            XCTAssertEqual(request.path, "/api/v1/workouts/fixture/power-curve")
            XCTAssertEqual(request.headerFields[.authorization], "Bearer synthetic")
            return (HTTPResponse(status: .ok, headerFields: [.contentType: "application/json; charset=utf-8"]), HTTPBody(bytes))
        })
        return try await api.powerCurve(token: "synthetic", id: "fixture")
    }
}

private actor ControlledCurve: PowerCurveService {
    private var pending: CheckedContinuation<PowerCurve, Error>?
    private var observer: CheckedContinuation<Void, Never>?
    func powerCurve(token: String, id: String) async throws -> PowerCurve {
        try await withCheckedThrowingContinuation { continuation in
            pending = continuation
            observer?.resume()
            observer = nil
        }
    }
    func waitForRequest() async {
        if pending != nil { return }
        await withCheckedContinuation { observer = $0 }
    }
    func respond(_ result: Result<PowerCurve, Error>) {
        let continuation = pending
        pending = nil
        continuation?.resume(with: result)
    }
}
