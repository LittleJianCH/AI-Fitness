import Foundation
import OpenAPIRuntime

/// Servant emits whole seconds or fractional seconds according to the value.
struct FitnessDateTranscoder: DateTranscoder {
    private let seconds: ISO8601DateTranscoder = .iso8601
    private let fractions: ISO8601DateTranscoder = .iso8601WithFractionalSeconds

    func decode(_ value: String) throws -> Date {
        guard let dot = value.firstIndex(of: ".") else { return try seconds.decode(value) }
        let start = value.index(after: dot)
        let end = value[start...].firstIndex { !("0"..."9").contains($0) } ?? value.endIndex
        guard start != end, let fraction = Double("0." + value[start..<end]) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Invalid fractional timestamp"))
        }
        // ISO8601DateFormatter can overflow on Aeson's 12 fractional digits.
        // Parse the whole-second instant (including its offset), then add the
        // fraction separately without reducing the backend's timestamp precision.
        let whole = String(value[..<dot]) + value[end...]
        return try seconds.decode(whole).addingTimeInterval(fraction)
    }

    func encode(_ value: Date) throws -> String {
        try fractions.encode(value)
    }
}
