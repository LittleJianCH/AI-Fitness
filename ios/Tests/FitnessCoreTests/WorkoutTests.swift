import ContractClient
import Foundation
import HTTPTypes
import OpenAPIRuntime
import XCTest
@testable import FitnessCore

final class WorkoutTests: XCTestCase {
    @MainActor
    func testPaginationDeduplicatesAndRetainsCursorAfterNetworkFailure() async throws {
        let cards = try await fixturePage().items
        var changed = cards[0]
        changed.userData.workoutTitle = "Changed title"
        let service = ControlledWorkouts()
        let session = await signedIn()
        let store = WorkoutListStore(service: service, session: session)
        let first = Task { await store.refresh(sport: .cycling) }
        await service.waitForRequests(1)
        await service.respond(0, .success(.init(items: [cards[0]], nextCursor: "next")))
        await first.value
        let failed = Task { await store.loadMore() }
        await service.waitForRequests(2)
        await service.respond(1, .failure(URLError(.notConnectedToInternet)))
        await failed.value
        XCTAssertEqual(store.items, [cards[0]])
        XCTAssertEqual(store.nextCursor, "next")
        XCTAssertNotNil(store.message)
        let more = Task { await store.loadMore() }
        await service.waitForRequests(3)
        await service.respond(2, .success(.init(items: [changed, cards[1]])))
        await more.value
        XCTAssertEqual(store.items, [changed, cards[1]])
        XCTAssertNil(store.nextCursor)
        XCTAssertNil(store.message)
        XCTAssertFalse(store.isLoading)
        let requests = await service.requests
        XCTAssertEqual(requests.map(\.cursor), [nil, "next", "next"])
        XCTAssertTrue(requests.allSatisfy { $0.sport == .cycling })
    }

    @MainActor
    func testLateFilterResponseCannotReplaceCurrentFilter() async throws {
        let cards = try await fixturePage().items
        let service = ControlledWorkouts()
        let store = WorkoutListStore(service: service, session: await signedIn())
        let cycling = Task { await store.refresh(sport: .cycling) }
        await service.waitForRequests(1)
        let running = Task { await store.refresh(sport: .running) }
        await service.waitForRequests(2)
        await service.respond(1, .success(.init(items: [cards[1]])))
        await running.value
        await service.respond(0, .success(.init(items: [cards[0]], nextCursor: "old")))
        await cycling.value
        XCTAssertEqual(store.items, [cards[1]])
        XCTAssertEqual(store.sport, .running)
        XCTAssertNil(store.nextCursor)
        XCTAssertFalse(store.isLoading)
    }

    @MainActor
    func testEarlierSessionCannotPublishDataOrRevokeNewSession() async throws {
        let cards = try await fixturePage().items
        let service = ControlledWorkouts()
        let session = await signedIn()
        let store = WorkoutListStore(service: service, session: session)
        let old = Task { await store.refresh(sport: nil) }
        await service.waitForRequests(1)
        session.forgetSavedSession()
        await session.login(username: "alice", password: "synthetic", deviceName: "Test")
        await service.respond(0, .success(.init(items: cards)))
        await old.value
        XCTAssertTrue(store.items.isEmpty)
        let staleError = Task { await store.refresh(sport: nil) }
        await service.waitForRequests(2)
        session.forgetSavedSession()
        await session.login(username: "alice", password: "synthetic", deviceName: "Test")
        await service.respond(1, .failure(APIResponseError(status: 401, problem: nil, retryAfter: nil)))
        await staleError.value
        XCTAssertNotNil(session.user)
        let currentError = Task { await store.refresh(sport: nil) }
        await service.waitForRequests(3)
        await service.respond(2, .failure(APIResponseError(status: 401, problem: nil, retryAfter: nil)))
        await currentError.value
        XCTAssertNil(session.user)
    }

    @MainActor
    func testCancelledListDoesNotPublishLateSuccess() async throws {
        let page = try await fixturePage()
        let service = ControlledWorkouts()
        let store = WorkoutListStore(service: service, session: await signedIn())
        let task = Task { await store.refresh(sport: nil) }
        await service.waitForRequests(1)
        task.cancel()
        await service.respond(0, .success(page))
        await task.value
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertNil(store.message)
        XCTAssertFalse(store.isLoading)
    }

    func testWorkoutWireRequestAndPresentationPreserveMeasurements() async throws {
        let bytes = try fixtureData("workout-response")
        let api = FitnessAPI(endpoint: try ServerEndpoint("https://fitness.invalid"), transport: FixtureTransport { request, _, _ in
            XCTAssertEqual(request.path, "/api/v1/workouts/00000000-0000-0000-0000-000000000001")
            XCTAssertEqual(request.headerFields[.authorization], "Bearer synthetic")
            return (HTTPResponse(status: .ok, headerFields: [.contentType: "application/json; charset=utf-8"]), HTTPBody(bytes))
        })
        let workout = try await api.workout(token: "synthetic", id: "00000000-0000-0000-0000-000000000001")
        XCTAssertEqual(workout.workoutRevision, "9007199254740993")
        let speed = try XCTUnwrap(workout.metrics.first { $0.id == "speed" })
        XCTAssertEqual(speed.points.map(\.timestamp), workout.motion.motionSpeed.map(\.timestamp))
        XCTAssertEqual(speed.points.map(\.value), workout.motion.motionSpeed.map { $0.value * 3.6 })
        let heartRate = try XCTUnwrap(workout.metrics.first { $0.id == "heartRate" })
        XCTAssertEqual(heartRate.points.map(\.value), workout.motion.motionHeartRate.map(\.value))
        XCTAssertNil(workout.workoutUserData.workoutNotes)
        XCTAssertEqual(WorkoutFormat.distance(nil), "无数据")
        XCTAssertNotEqual(WorkoutFormat.distance(0), "无数据")
        XCTAssertEqual(WorkoutFormat.duration(3661), "1:01:01")
        XCTAssertEqual(WorkoutFormat.pace(4), "4:10 /km")
        XCTAssertEqual(WorkoutFormat.pace(0), "无数据")
        XCTAssertEqual(WorkoutFormat.pace(.leastNonzeroMagnitude), "无数据")
        XCTAssertEqual(WorkoutFormat.duration(.infinity), "无数据")
    }

    @MainActor
    func testDetailFailureRetryAndSessionIsolation() async throws {
        let bytes = try fixtureData("workout-response")
        let api = FitnessAPI(endpoint: try ServerEndpoint("https://fitness.invalid"), transport: FixtureTransport { _, _, _ in
            (HTTPResponse(status: .ok, headerFields: [.contentType: "application/json; charset=utf-8"]), HTTPBody(bytes))
        })
        let workout = try await api.workout(token: "synthetic", id: "fixture")
        let service = ControlledWorkouts()
        let session = await signedIn()
        let store = WorkoutDetailStore(service: service, session: session)
        let failed = Task { await store.load(id: workout.workoutId) }
        await service.waitForDetail()
        await service.respondDetail(.failure(APIResponseError(status: 404, problem: nil, retryAfter: nil)))
        await failed.value
        XCTAssertNil(store.workout)
        XCTAssertNotNil(store.message)
        XCTAssertFalse(store.isLoading)
        let retry = Task { await store.load(id: workout.workoutId) }
        await service.waitForDetail()
        await service.respondDetail(.success(workout))
        await retry.value
        XCTAssertEqual(store.workout, workout)
        XCTAssertNil(store.message)
        let stale = Task { await store.load(id: workout.workoutId) }
        await service.waitForDetail()
        session.forgetSavedSession()
        await service.respondDetail(.success(workout))
        await stale.value
        XCTAssertNil(store.workout)
    }

    @MainActor
    private func signedIn() async -> SessionStore {
        let session = SessionStore(service: TestAuth(), vault: MemoryVault())
        await session.login(username: "alice", password: "synthetic", deviceName: "Test")
        return session
    }

    private func fixturePage() async throws -> WorkoutPage {
        let bytes = try fixtureData("list-response")
        let api = FitnessAPI(endpoint: try ServerEndpoint("https://fitness.invalid"), transport: FixtureTransport { request, _, _ in
            XCTAssertEqual(request.path, "/api/v1/workouts?sport=cycling&limit=50")
            XCTAssertEqual(request.headerFields[.authorization], "Bearer synthetic")
            return (HTTPResponse(status: .ok, headerFields: [.contentType: "application/json; charset=utf-8"]), HTTPBody(bytes))
        })
        return try await api.workouts(token: "synthetic", sport: .cycling, cursor: nil)
    }

    private func fixtureData(_ name: String) throws -> Data {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try Data(contentsOf: root.appendingPathComponent("backend/build/\(name).json"))
    }
}

private actor ControlledWorkouts: WorkoutService {
    struct Request: Sendable { let sport: WorkoutSportFilter?; let cursor: String? }
    var requests: [Request] = []
    var continuations: [Int: CheckedContinuation<WorkoutPage, Error>] = [:]
    var observer: (Int, CheckedContinuation<Void, Never>)?
    var detail: CheckedContinuation<Workout, Error>?
    var detailObserver: CheckedContinuation<Void, Never>?

    func waitForRequests(_ count: Int) async {
        if requests.count >= count { return }
        await withCheckedContinuation { observer = (count, $0) }
    }
    func respond(_ index: Int, _ result: Result<WorkoutPage, Error>) {
        continuations.removeValue(forKey: index)?.resume(with: result)
    }
    func workouts(token: String, sport: WorkoutSportFilter?, cursor: String?) async throws -> WorkoutPage {
        let index = requests.count
        requests.append(.init(sport: sport, cursor: cursor))
        return try await withCheckedThrowingContinuation { continuation in
            continuations[index] = continuation
            if let (count, waiting) = observer, requests.count >= count {
                observer = nil
                waiting.resume()
            }
        }
    }
    func waitForDetail() async {
        if detail != nil { return }
        await withCheckedContinuation { detailObserver = $0 }
    }
    func respondDetail(_ result: Result<Workout, Error>) {
        let pending = detail
        detail = nil
        pending?.resume(with: result)
    }
    func workout(token: String, id: String) async throws -> Workout {
        try await withCheckedThrowingContinuation { continuation in
            detail = continuation
            detailObserver?.resume()
            detailObserver = nil
        }
    }
}
