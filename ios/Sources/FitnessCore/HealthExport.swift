import ContractClient
import CryptoKit
import Foundation

public typealias HealthExportReceipt = Components.Schemas.ExportReceipt

public protocol HealthExportService: Sendable {
    func recordHealthExport(token: String, workoutID: String, revision: String, objectID: UUID) async throws -> HealthExportReceipt
}

extension FitnessAPI: HealthExportService {
    public func recordHealthExport(token: String, workoutID: String, revision: String, objectID: UUID) async throws -> HealthExportReceipt {
        try await apiCall {
            try await client(token: token).post_workouts_workoutId_export_receipts(
                path: .init(workoutId: workoutID),
                body: .application_json_charset_utf_hyphen_8(.init(externalId: objectID.uuidString.lowercased(), platform: .appleHealth, workoutRevision: revision)))
                .ok.body.application_json_charset_utf_hyphen_8
        }
    }
}

public enum HealthExportError: Error, Equatable, Sendable {
    case invalidData, busy, uncertainWorkout, uncertainRoute, invalidReceipt, storage

}

/// A revision is an explicit new export; a retry of that revision resumes one identity.
public struct HealthExportPlan: Codable, Sendable {
    public let identity: String
    public let scope: String
    public let workout: Workout
    public init(workout: Workout, origin: String, ownerID: String) throws {
        guard UUID(uuidString: workout.workoutId) != nil, workout.workoutRevision.first != "0", !workout.workoutRevision.isEmpty,
              workout.workoutRevision.allSatisfy({ $0 >= "0" && $0 <= "9" }),
              workout.workoutObservation.observationRange.rangeEnd > workout.workoutObservation.observationRange.rangeStart,
              workout.motion.motionPosition.count <= 50_000,
              workout.metrics.reduce(0, { $0 + $1.points.count }) <= 50_000 else { throw HealthExportError.invalidData }
        let identityData = try JSONEncoder().encode([origin, ownerID, workout.workoutId, String(workout.workoutRevision)])
        identity = SHA256.hash(data: identityData).map { String(format: "%02x", $0) }.joined()
        let scopeData = try JSONEncoder().encode([origin, ownerID, workout.workoutId])
        scope = SHA256.hash(data: scopeData).map { String(format: "%02x", $0) }.joined()
        self.workout = workout
    }
}

public enum HealthExportPhase: String, Codable, Sendable {
    case prepared, workoutAttempted, workoutSaved, routeAttempted, platformComplete, complete
}

public struct HealthExportRecord: Codable, Sendable {
    public let identity: String
    public let workoutID: String
    public let revision: String
    public var plan: HealthExportPlan?
    public var phase: HealthExportPhase
    public var objectID: UUID?
    public var receipt: HealthExportReceipt?
}

public protocol HealthExportJournal: Sendable {
    func read(identity: String) throws -> HealthExportRecord?
    func write(_ record: HealthExportRecord) throws
    func pending(scope: String) throws -> [HealthExportPlan]
}

/// Atomic, device-protected recovery state. Completed records contain no samples/routes.
public struct FileHealthExportJournal: HealthExportJournal {
    private let directory: URL
    public init(directory: URL) { self.directory = directory }
    public func pending(scope: String) throws -> [HealthExportPlan] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        do {
            return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
                .compactMap { url in
                    let record = try read(identity: url.deletingPathExtension().lastPathComponent)
                    guard let record, record.phase != .complete, let plan = record.plan, plan.scope == scope else { return nil }
                    return plan
                }
        } catch { throw HealthExportError.storage }
    }
    private func file(_ identity: String) throws -> URL {
        guard identity.count == 64, identity.allSatisfy({ $0.isHexDigit }) else { throw HealthExportError.storage }
        return directory.appendingPathComponent(identity).appendingPathExtension("json")
    }
    public func read(identity: String) throws -> HealthExportRecord? {
        let path = try file(identity)
        guard FileManager.default.fileExists(atPath: path.path) else { return nil }
        do {
            let record = try JSONDecoder().decode(HealthExportRecord.self, from: Data(contentsOf: path))
            guard record.identity == identity else { throw HealthExportError.storage }
            return record
        } catch { throw HealthExportError.storage }
    }
    public func write(_ record: HealthExportRecord) throws {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var root = directory
            var resources = URLResourceValues()
            resources.isExcludedFromBackup = true
            try root.setResourceValues(resources)
            #if os(iOS)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: directory.path)
            try JSONEncoder().encode(record).write(to: file(record.identity), options: [.atomic, .completeFileProtection])
            #else
            try JSONEncoder().encode(record).write(to: file(record.identity), options: .atomic)
            #endif
        } catch { throw HealthExportError.storage }
    }
}

public protocol HealthExportWriter: Sendable {
    func authorize(plan: HealthExportPlan) async throws
    func findWorkout(plan: HealthExportPlan) async throws -> UUID?
    func createWorkout(plan: HealthExportPlan, beforeCommit: @Sendable () async throws -> Void) async throws -> UUID?
    func findRoute(plan: HealthExportPlan, workoutID: UUID) async throws -> Bool
    func createRoute(plan: HealthExportPlan, workoutID: UUID, beforeCommit: @Sendable () async throws -> Void) async throws
}

/// One process-wide coordinator serializes attempts for each export identity.
public actor HealthExportCoordinator {
    private let journal: any HealthExportJournal
    private var active: Set<String> = []
    public init(journal: any HealthExportJournal) { self.journal = journal }

    public func planToResume(_ requested: HealthExportPlan) throws -> HealthExportPlan {
        try journal.pending(scope: requested.scope).first ?? requested
    }

    public func export(_ requested: HealthExportPlan, token: String, service: any HealthExportService,
                       writer: any HealthExportWriter) async throws -> HealthExportReceipt {
        let key = requested.identity
        guard active.insert(key).inserted else { throw HealthExportError.busy }
        defer { active.remove(key) }
        try Task.checkCancellation()
        var record = try journal.read(identity: key) ?? HealthExportRecord(
            identity: key, workoutID: requested.workout.workoutId, revision: requested.workout.workoutRevision,
            plan: requested, phase: .prepared)
        if record.phase == .complete, let receipt = record.receipt { return receipt }
        guard let plan = record.plan, plan.identity == key,
              record.workoutID == requested.workout.workoutId, record.revision == requested.workout.workoutRevision else {
            throw HealthExportError.storage
        }
        try journal.write(record)
        if record.phase != .platformComplete {
            try await writer.authorize(plan: plan)
            try Task.checkCancellation()
        }
        if record.phase == .prepared {
            let existing = try await writer.findWorkout(plan: plan)
            try Task.checkCancellation()
            let object: UUID?
            if let existing { object = existing }
            else { object = try await writer.createWorkout(plan: plan) { try await self.mark(key, phase: .workoutAttempted) } }
            guard let object else { throw HealthExportError.uncertainWorkout }
            record.objectID = object
            record.phase = .workoutSaved
            try journal.write(record)
        } else if record.phase == .workoutAttempted {
            guard let object = try await writer.findWorkout(plan: plan) else { throw HealthExportError.uncertainWorkout }
            record.objectID = object
            record.phase = .workoutSaved
            try journal.write(record)
        }
        guard let object = record.objectID else { throw HealthExportError.storage }
        try Task.checkCancellation()
        if record.phase == .workoutSaved, !plan.workout.motion.motionPosition.isEmpty {
            if try await !writer.findRoute(plan: plan, workoutID: object) {
                try Task.checkCancellation()
                try await writer.createRoute(plan: plan, workoutID: object) { try await self.mark(key, phase: .routeAttempted) }
            }
        } else if record.phase == .routeAttempted {
            guard try await writer.findRoute(plan: plan, workoutID: object) else { throw HealthExportError.uncertainRoute }
        }
        record.phase = .platformComplete
        try journal.write(record)
        try Task.checkCancellation()
        let receipt = try await service.recordHealthExport(token: token, workoutID: record.workoutID, revision: record.revision, objectID: object)
        guard receipt.workoutId == record.workoutID, receipt.workoutRevision == record.revision,
              UUID(uuidString: receipt.externalId) == object, receipt.platform == .appleHealth else {
            throw HealthExportError.invalidReceipt
        }
        // Commit acknowledgement even if the view was cancelled while HTTP completed.
        record.phase = .complete
        record.receipt = receipt
        record.plan = nil
        try journal.write(record)
        return receipt
    }

    private func mark(_ identity: String, phase: HealthExportPhase) throws {
        try Task.checkCancellation()
        guard var record = try journal.read(identity: identity) else { throw HealthExportError.storage }
        record.phase = phase
        try journal.write(record)
    }
}
