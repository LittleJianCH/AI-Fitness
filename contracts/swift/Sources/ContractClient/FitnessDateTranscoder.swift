import Foundation
import OpenAPIRuntime

/// Servant emits whole seconds or fractional seconds according to the value.
struct FitnessDateTranscoder: DateTranscoder {
    private let seconds: ISO8601DateTranscoder = .iso8601
    private let fractions: ISO8601DateTranscoder = .iso8601WithFractionalSeconds

    func decode(_ value: String) throws -> Date {
        do {
            return try fractions.decode(value)
        } catch {
            return try seconds.decode(value)
        }
    }

    func encode(_ value: Date) throws -> String {
        try fractions.encode(value)
    }
}
