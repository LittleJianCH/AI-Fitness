import ContractClient

public typealias HealthImportRecord = Components.Schemas.ImportRecord

public protocol HealthImportService: WorkoutService {
    func submitHealthKit(token: String, submission: Components.Schemas.HealthKitSubmission) async throws -> HealthImportRecord
    func importRecord(token: String, id: String) async throws -> HealthImportRecord
}

extension FitnessAPI: HealthImportService {
    public func submitHealthKit(token: String, submission: Components.Schemas.HealthKitSubmission) async throws -> HealthImportRecord {
        try await apiCall {
            try await client(token: token).post_imports_healthkit(body: .application_json_charset_utf_hyphen_8(submission))
                .ok.body.application_json_charset_utf_hyphen_8
        }
    }
    public func importRecord(token: String, id: String) async throws -> HealthImportRecord {
        try await apiCall {
            try await client(token: token).get_imports_importId(path: .init(importId: id))
                .ok.body.application_json_charset_utf_hyphen_8
        }
    }
}
