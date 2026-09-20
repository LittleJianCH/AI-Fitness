import ContractClient
import Foundation
import Observation

public enum HealthImportAction { case normal, retry, refresh }

@MainActor @Observable
public final class HealthImportStore {
    public private(set) var records: [String: HealthImportRecord] = [:]
    public private(set) var messages: [String: ClientIssue] = [:]
    public private(set) var activeID: String?
    public private(set) var pauseBatch = false
    @ObservationIgnored private let service: any HealthImportService
    @ObservationIgnored private let session: SessionStore

    public init(service: any HealthImportService, session: SessionStore) {
        self.service = service; self.session = session
    }

    public func upload(_ preview: HealthImportPreview, action: HealthImportAction = .normal) async {
        guard activeID == nil, let token = session.token, session.user != nil else { return }
        let identity = session.generation
        activeID = preview.id
        pauseBatch = false
        messages[preview.id] = nil
        defer { activeID = nil }
        do {
            try Task.checkCancellation()
            var submission = preview.submission
            switch action {
            case .normal: break
            case .retry:
                guard let record = records[preview.id], record.status == .failed, record.lastSuccess == nil else { return }
                submission.intent = .retry
                submission.expectedRevision = record.revision
            case .refresh:
                guard let record = records[preview.id], let output = record.lastSuccess, output.parts.count == 1,
                      let part = output.parts.first, part.partKey == "workout" else { return }
                let workout = try await service.workout(token: token, id: part.workoutId)
                guard session.generation == identity else { return }
                try Task.checkCancellation()
                submission.intent = .refresh
                submission.expectedRevision = record.revision
                submission.expectedWorkouts = [.init(id: workout.workoutId, revision: workout.workoutRevision)]
            }
            let record = try await service.submitHealthKit(token: token, submission: submission)
            guard session.generation == identity else { return }
            try Task.checkCancellation()
            guard case .case2(let source) = record.source,
                  source.data.objectId.lowercased() == preview.id else { throw HealthImportError.invalidAcknowledgement }
            if let output = record.lastSuccess {
                guard output.groupId == nil, output.parts.count == 1, let part = output.parts.first,
                      part.partKey == "workout", UUID(uuidString: part.workoutId) != nil else {
                    throw HealthImportError.invalidAcknowledgement
                }
            } else if record.status == .succeeded { throw HealthImportError.invalidAcknowledgement }
            records[preview.id] = record
            switch record.status {
            case .succeeded:
                messages[preview.id] = .importConfirmed
            case .failed:
                messages[preview.id] = .importFailed
            case .suppressed:
                messages[preview.id] = .importSuppressed
            case .pending, .processing:
                messages[preview.id] = .importPending
            }
        } catch {
            guard session.generation == identity else { return }
            if (error as? APIResponseError)?.status == 401 { session.handleUnauthorized(for: identity) }
            else if !(error is CancellationError) {
                messages[preview.id] = ClientIssue(error)
                pauseBatch = (error as? APIResponseError)?.status == 429
            }
        }
    }
}
