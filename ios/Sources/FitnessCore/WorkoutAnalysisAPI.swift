import ContractClient

public typealias WorkoutAnalysis = Components.Schemas.WorkoutAnalysis
public typealias MetricAnalysis = Components.Schemas.MetricAnalysis

public protocol WorkoutAnalysisService: Sendable {
    func workoutAnalysis(token: String, id: String) async throws -> WorkoutAnalysis
}

extension FitnessAPI: WorkoutAnalysisService {
    public func workoutAnalysis(token: String, id: String) async throws -> WorkoutAnalysis {
        try await apiCall {
            try await client(token: token).get_workouts_workoutId_analysis(path: .init(workoutId: id))
                .ok.body.application_json_charset_utf_hyphen_8
        }
    }
}
