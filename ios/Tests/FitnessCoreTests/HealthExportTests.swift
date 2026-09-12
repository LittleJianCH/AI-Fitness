import ContractClient
import Foundation
import HTTPTypes
import OpenAPIRuntime
import XCTest
@testable import FitnessCore

final class HealthExportTests: XCTestCase {
    func testReceiptWireUsesExactRevisionAndPlatformObjectIdentity() async throws {
        let object = UUID()
        let wid = HealthImportTests.workoutID
        let api = FitnessAPI(endpoint: try ServerEndpoint("https://fitness.invalid"), transport: FixtureTransport { request, body, _ in
            XCTAssertEqual(request.path, "/api/v1/workouts/\(wid)/export-receipts")
            XCTAssertEqual(request.headerFields[.authorization], "Bearer synthetic")
            let data = try await Data(collecting: XCTUnwrap(body), upTo: 4_096)
            let values = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
            XCTAssertEqual(values, ["externalId": object.uuidString.lowercased(), "platform": "appleHealth", "workoutRevision": "123456789012345678901234567890"])
            return (HTTPResponse(status: .serviceUnavailable), HTTPBody("unavailable"))
        })
        do { _ = try await api.recordHealthExport(token: "synthetic", workoutID: wid, revision: "123456789012345678901234567890", objectID: object); XCTFail() }
        catch let error as APIResponseError { XCTAssertEqual(error.status, 503) }
    }

    func testProjectionUsesTotalsOnceAndKeepsMissingMeasurements() throws {
        let plan = try plan()
        let quantities = try plan.quantities()
        XCTAssertEqual(quantities.filter { $0.kind == .distanceCycling }.map(\.value), [1_000])
        XCTAssertEqual(quantities.filter { $0.kind == .heartRate }.map(\.value), [120])
        XCTAssertTrue(quantities.filter { $0.kind == .activeEnergyBurned }.isEmpty)
        XCTAssertEqual(quantities.first?.start, HealthImportTests.at(5))
        let other = try HealthExportPlan(workout: plan.workout, origin: "https://other.invalid", ownerID: "alice")
        XCTAssertNotEqual(plan.identity, other.identity)
        let otherOwner = try HealthExportPlan(workout: plan.workout, origin: "https://fitness.invalid", ownerID: "bob")
        XCTAssertNotEqual(plan.identity, otherOwner.identity)
    }

    func testReceiptFailureAndRestartDoNotRewritePlatformData() async throws {
        let (journal, root) = temporaryJournal()
        defer { try? FileManager.default.removeItem(at: root) }
        let plan = try plan()
        let writer = ExportWriterStub()
        let service = ExportServiceStub()
        await service.failOnce()
        do { _ = try await HealthExportCoordinator(journal: journal).export(plan, token: "synthetic", service: service, writer: writer); XCTFail() }
        catch { }
        XCTAssertEqual(try journal.read(identity: plan.identity)?.phase, .platformComplete)
        var edited = plan.workout
        edited.workoutRevision = "2"
        let requested = try HealthExportPlan(workout: edited, origin: "https://fitness.invalid", ownerID: "alice")
        let resumed = try await HealthExportCoordinator(journal: journal).planToResume(requested)
        XCTAssertEqual(resumed.workout.workoutRevision, "1")
        let receipt = try await HealthExportCoordinator(journal: journal).export(plan, token: "synthetic", service: service, writer: writer)
        XCTAssertEqual(receipt.workoutRevision, "1")
        let count = await writer.creates
        XCTAssertEqual(count, 1)
        let stored = try XCTUnwrap(journal.read(identity: plan.identity))
        XCTAssertEqual(stored.phase, .complete)
        XCTAssertNil(stored.plan)
        let next = try await HealthExportCoordinator(journal: journal).planToResume(requested)
        XCTAssertEqual(next.workout.workoutRevision, "2")
        _ = try await HealthExportCoordinator(journal: journal).export(plan, token: "synthetic", service: service, writer: writer)
        let requests = await service.requests
        XCTAssertEqual(requests, 2)
    }

    func testUnknownWorkoutWriteOnlyQueriesOnRetry() async throws {
        let (journal, root) = temporaryJournal()
        defer { try? FileManager.default.removeItem(at: root) }
        let plan = try plan()
        let writer = ExportWriterStub()
        await writer.setUnknownWorkout()
        let service = ExportServiceStub()
        let coordinator = HealthExportCoordinator(journal: journal)
        for _ in 0..<2 {
            do { _ = try await coordinator.export(plan, token: "synthetic", service: service, writer: writer); XCTFail() }
            catch HealthExportError.uncertainWorkout { }
        }
        let count = await writer.creates
        XCTAssertEqual(count, 1)
        XCTAssertEqual(try journal.read(identity: plan.identity)?.phase, .workoutAttempted)
        await writer.revealWorkout()
        _ = try await coordinator.export(plan, token: "synthetic", service: service, writer: writer)
        let after = await writer.creates
        XCTAssertEqual(after, 1)
    }

    func testPartialRouteRecoversWithoutRepeatingWorkoutOrRoute() async throws {
        let (journal, root) = temporaryJournal()
        defer { try? FileManager.default.removeItem(at: root) }
        let plan = try plan(route: true)
        let writer = ExportWriterStub()
        await writer.setUnknownRoute()
        let service = ExportServiceStub()
        let coordinator = HealthExportCoordinator(journal: journal)
        do { _ = try await coordinator.export(plan, token: "synthetic", service: service, writer: writer); XCTFail() }
        catch { }
        XCTAssertEqual(try journal.read(identity: plan.identity)?.phase, .routeAttempted)
        _ = try await coordinator.export(plan, token: "synthetic", service: service, writer: writer)
        let creates = await writer.creates
        let routes = await writer.routes
        XCTAssertEqual(creates, 1)
        XCTAssertEqual(routes, 1)
    }

    func testFailureBeforeCommitCanRetryAndCancellationDoesNotAcknowledge() async throws {
        let (journal, root) = temporaryJournal()
        defer { try? FileManager.default.removeItem(at: root) }
        let plan = try plan()
        let writer = ExportWriterStub()
        await writer.failBeforeCommit()
        let service = ExportServiceStub()
        let coordinator = HealthExportCoordinator(journal: journal)
        do { _ = try await coordinator.export(plan, token: "synthetic", service: service, writer: writer); XCTFail() }
        catch { }
        XCTAssertEqual(try journal.read(identity: plan.identity)?.phase, .prepared)
        _ = try await coordinator.export(plan, token: "synthetic", service: service, writer: writer)
        let requests = await service.requests
        XCTAssertEqual(requests, 1)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await coordinator.export(plan, token: "synthetic", service: service, writer: writer)
        }
        do { _ = try await task.value; XCTFail() } catch is CancellationError { }
    }

    private func temporaryJournal() -> (FileHealthExportJournal, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return (FileHealthExportJournal(directory: root), root)
    }
    private func plan(route: Bool = false) throws -> HealthExportPlan {
        var input = HealthImportTests.input()
        input.summary.summaryDistance = 1_000
        input.heartRate = [.init(start: HealthImportTests.at(5), end: HealthImportTests.at(5), value: 120)]
        input.distance = [.init(start: HealthImportTests.at(0), end: HealthImportTests.at(10), value: 20)]
        if route { input.locations = [.init(timestamp: HealthImportTests.at(5), latitude: 30, longitude: 120, altitude: nil)] }
        let preview = try input.preview()
        let workout = Workout(workoutId: HealthImportTests.workoutID, workoutObservation: preview.observation,
                              workoutRevision: "1", workoutUserData: preview.submission.parts[0].initialUserData)
        return try HealthExportPlan(workout: workout, origin: "https://fitness.invalid", ownerID: "alice")
    }
}

private actor ExportWriterStub: HealthExportWriter {
    var creates = 0
    var routes = 0
    var unknownWorkout = false
    var unknownRoute = false
    var earlyFailure = false
    var visible = false
    let object = UUID()
    func setUnknownWorkout() { unknownWorkout = true }
    func setUnknownRoute() { unknownRoute = true }
    func revealWorkout() { visible = true }
    func failBeforeCommit() { earlyFailure = true }
    func authorize(plan: HealthExportPlan) async throws { }
    func findWorkout(plan: HealthExportPlan) async throws -> UUID? { visible ? object : nil }
    func createWorkout(plan: HealthExportPlan, beforeCommit: @Sendable () async throws -> Void) async throws -> UUID? {
        creates += 1
        if earlyFailure { earlyFailure = false; throw HealthExportError.invalidData }
        try await beforeCommit()
        if unknownWorkout { return nil }
        visible = true
        return object
    }
    func findRoute(plan: HealthExportPlan, workoutID: UUID) async throws -> Bool { routes == 1 }
    func createRoute(plan: HealthExportPlan, workoutID: UUID, beforeCommit: @Sendable () async throws -> Void) async throws {
        try await beforeCommit()
        routes += 1
        if unknownRoute { throw HealthExportError.uncertainRoute }
    }
}

private actor ExportServiceStub: HealthExportService {
    var requests = 0
    var failure = false
    func failOnce() { failure = true }
    func recordHealthExport(token: String, workoutID: String, revision: String, objectID: UUID) async throws -> HealthExportReceipt {
        requests += 1
        if failure { failure = false; throw HealthExportError.invalidReceipt }
        return .init(exportedAt: HealthImportTests.at(100), externalId: objectID.uuidString, id: UUID().uuidString,
                     platform: .appleHealth, workoutId: workoutID, workoutRevision: revision)
    }
}
