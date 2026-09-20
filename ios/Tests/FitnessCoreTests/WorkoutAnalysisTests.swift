import Foundation
import HTTPTypes
import OpenAPIRuntime
import XCTest
@testable import FitnessCore

final class WorkoutAnalysisTests: XCTestCase {
    func testGeneratedRequestAndBackendResponse() async throws {
        let curve = try await fixture()
        XCTAssertEqual(curve.analysisRevision, "9007199254740993")
        XCTAssertEqual(curve.analysisPower.powerNormalized, 200)
        XCTAssertEqual(curve.analysisHeart.heartLoadStatus, .heartExcluded)
        XCTAssertEqual(curve.analysisSettingsRevision, "0")
    }

    @MainActor
    func testFailureRetryAndRevisionMismatch() async throws {
        let curve = try await fixture()
        let service = ControlledAnalysis()
        let store = WorkoutAnalysisStore(service: service, session: await signedIn())
        let failed = Task { await store.load(id: curve.analysisWorkoutId, revision: curve.analysisRevision) }
        await service.waitForRequest()
        await service.respond(.failure(URLError(.notConnectedToInternet)))
        await failed.value
        XCTAssertNotNil(store.message)
        XCTAssertNil(store.analysis)
        let retry = Task { await store.load(id: curve.analysisWorkoutId, revision: curve.analysisRevision) }
        await service.waitForRequest()
        await service.respond(.success(curve))
        await retry.value
        XCTAssertEqual(store.analysis, curve)
        XCTAssertNil(store.message)
        let mismatch = Task { await store.load(id: curve.analysisWorkoutId, revision: "2") }
        await service.waitForRequest()
        await service.respond(.success(curve))
        await mismatch.value
        XCTAssertNil(store.analysis)
        XCTAssertTrue(store.needsWorkoutRefresh)
        XCTAssertFalse(store.isLoading)
    }

    @MainActor
    func testCancellationAndSessionChangesDiscardLateResults() async throws {
        let curve = try await fixture()
        let service = ControlledAnalysis()
        let session = await signedIn()
        let store = WorkoutAnalysisStore(service: service, session: session)
        let cancelled = Task { await store.load(id: curve.analysisWorkoutId, revision: curve.analysisRevision) }
        await service.waitForRequest()
        cancelled.cancel()
        await service.respond(.success(curve))
        await cancelled.value
        XCTAssertNil(store.analysis)
        XCTAssertEqual(store.message, .analysisCancelled)
        let stale = Task { await store.load(id: curve.analysisWorkoutId, revision: curve.analysisRevision) }
        await service.waitForRequest()
        session.forgetSavedSession()
        await service.respond(.success(curve))
        await stale.value
        XCTAssertNil(store.analysis)
        XCTAssertFalse(store.isLoading)
    }

    @MainActor
    func testUnauthorizedExpiresOnlyCurrentSession() async throws {
        let service = ControlledAnalysis()
        let session = await signedIn()
        let store = WorkoutAnalysisStore(service: service, session: session)
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

    private func fixture() async throws -> WorkoutAnalysis {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let bytes = try Data(contentsOf: root.appendingPathComponent("backend/build/analysis-response.json"))
        let api = FitnessAPI(endpoint: try ServerEndpoint("https://fitness.invalid"), transport: FixtureTransport { request, _, _ in
            XCTAssertEqual(request.path, "/api/v1/workouts/fixture/analysis")
            XCTAssertEqual(request.headerFields[.authorization], "Bearer synthetic")
            return (HTTPResponse(status: .ok, headerFields: [.contentType: "application/json; charset=utf-8"]), HTTPBody(bytes))
        })
        return try await api.workoutAnalysis(token: "synthetic", id: "fixture")
    }
}

private actor ControlledAnalysis: WorkoutAnalysisService {
    private var pending: CheckedContinuation<WorkoutAnalysis, Error>?
    private var observer: CheckedContinuation<Void, Never>?
    func workoutAnalysis(token: String, id: String) async throws -> WorkoutAnalysis {
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
    func respond(_ result: Result<WorkoutAnalysis, Error>) {
        let continuation = pending
        pending = nil
        continuation?.resume(with: result)
    }
}
