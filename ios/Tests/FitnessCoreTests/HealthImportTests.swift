import ContractClient
import Foundation
import HTTPTypes
import OpenAPIRuntime
import XCTest
@testable import FitnessCore

final class HealthImportTests: XCTestCase {
    func testProjectionKeepsReportedSummaryAndIndependentSampleTimes() throws {
        var input = Self.input()
        input.summary.summaryDistance = 1_000
        input.heartRate = [.init(start: Self.at(1), end: Self.at(2), value: 120)]
        input.power = [.init(start: Self.at(3), end: Self.at(3), value: 150)]
        input.distance = [.init(start: Self.at(0), end: Self.at(10), value: 20), .init(start: Self.at(10), end: Self.at(20), value: 30)]
        input.energy = [.init(start: Self.at(0), end: Self.at(10), value: 4_184)]
        let preview = try input.preview()
        XCTAssertEqual(preview.summary.summaryDistance, 1_000)
        XCTAssertEqual(preview.motion.motionDistance.map(\.value), [20, 50])
        XCTAssertEqual(preview.motion.motionHeartRate.first?.timestamp, Self.at(2))
        XCTAssertEqual(preview.motion.motionPower.first?.timestamp, Self.at(3))
        XCTAssertEqual(preview.motion.motionEnergy.first?.value, 4_184)
        XCTAssertTrue(preview.motion.motionSpeed.isEmpty)
        XCTAssertNil(preview.summary.summaryMovingTime)
        XCTAssertEqual(preview.submission.intent, .normal)
        XCTAssertNil(preview.submission.expectedRevision)
        XCTAssertEqual(preview.submission.parts.first?.partKey, "workout")
        if case .case1(let cycling) = preview.observation.observationSport {
            XCTAssertNil(cycling.data.cyclingSummary.calculatedSummary)
        } else { XCTFail("Expected cycling projection") }
    }

    func testProjectionRejectsAmbiguityInsteadOfInventingMergedMeasurements() throws {
        var input = Self.input()
        input.distance = [.init(start: Self.at(0), end: Self.at(10), value: 20), .init(start: Self.at(5), end: Self.at(20), value: 30)]
        XCTAssertThrowsError(try input.preview())
        input.distance = []
        input.heartRate = [.init(start: Self.at(1), end: Self.at(1), value: 120), .init(start: Self.at(1), end: Self.at(1), value: 121)]
        XCTAssertThrowsError(try input.preview())
        input.heartRate = [.init(start: Self.at(-1), end: Self.at(1), value: 120)]
        XCTAssertThrowsError(try input.preview())
        input.heartRate = [.init(start: Self.at(1), end: Self.at(1), value: .nan)]
        XCTAssertThrowsError(try input.preview())
        let running = try Self.input(sport: .running).preview()
        guard case .case2(let sport) = running.observation.observationSport else { return XCTFail("Expected running") }
        XCTAssertTrue(sport.data.runningCadence.isEmpty)
        XCTAssertNil(sport.data.runningSummary.recordedSummary.summaryRunningCadence.averageValue)
    }

    @MainActor
    func testFailureRequiresExplicitRetryAndRefreshUsesCurrentWorkoutRevision() async throws {
        let preview = try Self.input().preview()
        let service = HealthImportStub()
        await service.set(.success(Self.record(preview, status: .failed)))
        let store = HealthImportStore(service: service, session: await session())
        await store.upload(preview)
        XCTAssertEqual(store.records[preview.id]?.status, .failed)
        XCTAssertFalse(store.messages[preview.id]?.contains("已确认") ?? true)
        await service.set(.success(Self.record(preview, status: .succeeded)))
        await store.upload(preview, action: .retry)
        var sent = await service.sent
        XCTAssertEqual(sent.last?.intent, .retry)
        XCTAssertEqual(sent.last?.expectedRevision, "2")
        XCTAssertTrue(sent.last?.expectedWorkouts.isEmpty == true)
        await store.upload(preview, action: .refresh)
        sent = await service.sent
        XCTAssertEqual(sent.last?.intent, .refresh)
        XCTAssertEqual(sent.last?.expectedWorkouts.first?.revision, "5")
        XCTAssertEqual(sent.last?.expectedWorkouts.first?.id, Self.workoutID)
    }

    @MainActor
    func testPendingSuppressionMalformedAcknowledgementAndThrottlingNeverClaimSuccess() async throws {
        let preview = try Self.input().preview()
        let service = HealthImportStub()
        let store = HealthImportStore(service: service, session: await session())
        for status in [Components.Schemas.ImportStatus.pending, .processing, .suppressed] {
            await service.set(.success(Self.record(preview, status: status)))
            await store.upload(preview)
            XCTAssertFalse(store.messages[preview.id]?.contains("已确认导入") ?? true)
        }
        var malformed = Self.record(preview, status: .succeeded)
        malformed.lastSuccess = nil
        await service.set(.success(malformed))
        await store.upload(preview)
        XCTAssertEqual(store.records[preview.id]?.status, .suppressed)
        XCTAssertEqual(store.messages[preview.id], HealthImportError.invalidAcknowledgement.errorDescription)
        await service.set(.failure(APIResponseError(status: 429, problem: nil, retryAfter: "60")))
        await store.upload(preview)
        XCTAssertTrue(store.pauseBatch)
    }

    @MainActor
    func testLateResponseCannotPublishIntoAnotherSession() async throws {
        let preview = try Self.input().preview()
        let service = HealthImportStub()
        await service.pause()
        let session = await session()
        let store = HealthImportStore(service: service, session: session)
        let task = Task { await store.upload(preview) }
        await service.waitForRequest()
        session.forgetSavedSession()
        await session.login(username: "alice", password: "synthetic", deviceName: "Test")
        await service.resume(.success(Self.record(preview, status: .succeeded)))
        await task.value
        XCTAssertTrue(store.records.isEmpty)
        XCTAssertTrue(store.messages.isEmpty)
        XCTAssertNil(store.activeID)
    }

    @MainActor
    func testCancellationDoesNotClaimLatePublication() async throws {
        let preview = try Self.input().preview()
        let service = HealthImportStub()
        await service.pause()
        let store = HealthImportStore(service: service, session: await session())
        let task = Task { await store.upload(preview) }
        await service.waitForRequest()
        task.cancel()
        await service.resume(.success(Self.record(preview, status: .succeeded)))
        await task.value
        XCTAssertTrue(store.records.isEmpty)
        XCTAssertTrue(store.messages.isEmpty)
        XCTAssertNil(store.activeID)
    }

    func testDedicatedEndpointEncodesSourceUUIDWithoutInventingWorkoutIdentity() async throws {
        let preview = try Self.input().preview()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let response = try encoder.encode(Self.record(preview, status: .succeeded))
        let api = FitnessAPI(endpoint: try ServerEndpoint("https://fitness.invalid"), transport: FixtureTransport { request, body, _ in
            XCTAssertEqual(request.path, "/api/v1/imports/healthkit")
            XCTAssertEqual(request.headerFields[.authorization], "Bearer synthetic")
            let bytes = try await Data(collecting: XCTUnwrap(body), upTo: 100_000)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
            XCTAssertEqual(object["objectId"] as? String, preview.id)
            XCTAssertNil(object["workoutId"])
            XCTAssertNil(object["expectedRevision"])
            XCTAssertEqual(object["intent"] as? String, "normal")
            return (HTTPResponse(status: .ok, headerFields: [.contentType: "application/json; charset=utf-8"]), HTTPBody(response))
        })
        let record = try await api.submitHealthKit(token: "synthetic", submission: preview.submission)
        XCTAssertEqual(record.status, .succeeded)
    }

    @MainActor private func session() async -> SessionStore {
        let value = SessionStore(service: TestAuth(), vault: MemoryVault())
        await value.login(username: "alice", password: "synthetic", deviceName: "Test")
        return value
    }
    static let workoutID = "00000000-0000-0000-0000-000000000011"
    static func at(_ seconds: Double) -> Date { Date(timeIntervalSince1970: 1_780_000_000 + seconds) }
    static func input(sport: HealthSport = .cycling) -> HealthObservationInput {
        .init(objectID: UUID(), sport: sport, start: at(0), end: at(100), timerDuration: 90)
    }
    static func record(_ preview: HealthImportPreview, status: Components.Schemas.ImportStatus) -> HealthImportRecord {
        .init(archive: .notApplicable, createdAt: at(0), id: "00000000-0000-0000-0000-000000000012",
              lastSuccess: status == .succeeded ? .init(importedAt: at(100), parserVersion: "healthkit-normalized-v1", parts: [.init(partKey: "workout", workoutId: workoutID)]) : nil,
              revision: "2", source: .case2(.init(data: .init(objectId: preview.id), _type: .healthKit)), status: status, updatedAt: at(100))
    }
}

private actor HealthImportStub: HealthImportService {
    var result: Result<HealthImportRecord, Error> = .failure(URLError(.notConnectedToInternet))
    var sent: [Components.Schemas.HealthKitSubmission] = []
    var paused = false
    var continuation: CheckedContinuation<HealthImportRecord, Error>?
    var observer: CheckedContinuation<Void, Never>?
    func set(_ value: Result<HealthImportRecord, Error>) { result = value }
    func pause() { paused = true }
    func waitForRequest() async {
        if continuation != nil { return }
        await withCheckedContinuation { observer = $0 }
    }
    func resume(_ value: Result<HealthImportRecord, Error>) { continuation?.resume(with: value); continuation = nil }
    func submitHealthKit(token: String, submission: Components.Schemas.HealthKitSubmission) async throws -> HealthImportRecord {
        sent.append(submission)
        if paused {
            return try await withCheckedThrowingContinuation {
                continuation = $0; observer?.resume(); observer = nil
            }
        }
        return try result.get()
    }
    func importRecord(token: String, id: String) async throws -> HealthImportRecord { try result.get() }
    func workouts(token: String, sport: WorkoutSportFilter?, cursor: String?) async throws -> WorkoutPage { .init(items: []) }
    func workout(token: String, id: String) async throws -> Workout {
        .init(workoutId: HealthImportTests.workoutID, workoutObservation: try HealthImportTests.input().preview().observation,
              workoutRevision: "5", workoutUserData: .init(statisticsInclusion: .includeInStatistics, workoutTags: []))
    }
}
