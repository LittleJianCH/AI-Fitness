import ContractClient
import Foundation

public typealias Workout = Components.Schemas.Workout
public typealias WorkoutCard = Components.Schemas.WorkoutCard
public typealias WorkoutPage = Components.Schemas.Page_WorkoutCard
public typealias WorkoutSportFilter = Operations.get_workouts.Input.Query.sportPayload

public protocol WorkoutService: Sendable {
    func workouts(token: String, sport: WorkoutSportFilter?, cursor: String?) async throws -> WorkoutPage
    func workout(token: String, id: String) async throws -> Workout
}

extension FitnessAPI: WorkoutService {
    public func workouts(token: String, sport: WorkoutSportFilter?, cursor: String?) async throws -> WorkoutPage {
        try await apiCall {
            try await client(token: token).get_workouts(query: .init(sport: sport, cursor: cursor, limit: 50))
                .ok.body.application_json_charset_utf_hyphen_8
        }
    }

    public func workout(token: String, id: String) async throws -> Workout {
        try await apiCall {
            try await client(token: token).get_workouts_workoutId(path: .init(workoutId: id))
                .ok.body.application_json_charset_utf_hyphen_8
        }
    }
}
