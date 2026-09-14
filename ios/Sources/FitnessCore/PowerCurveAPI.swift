import ContractClient

public typealias PowerCurve = Components.Schemas.PowerCurve
public typealias PowerCurvePoint = Components.Schemas.PowerCurvePoint

public protocol PowerCurveService: Sendable {
    func powerCurve(token: String, id: String) async throws -> PowerCurve
}

extension FitnessAPI: PowerCurveService {
    public func powerCurve(token: String, id: String) async throws -> PowerCurve {
        try await apiCall {
            try await client(token: token).get_workouts_workoutId_power_curve(path: .init(workoutId: id))
                .ok.body.application_json_charset_utf_hyphen_8
        }
    }
}
