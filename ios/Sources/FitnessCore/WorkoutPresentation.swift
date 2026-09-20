import ContractClient
import Foundation

public struct MetricPoint: Identifiable, Sendable {
    public var id: Date { timestamp }
    public let timestamp: Date
    public let value: Double
}

public struct WorkoutMetric: Identifiable, Sendable {
    public let id: String
    public let title: MetricLabel
    public let unit: String
    public let points: [MetricPoint]

    /// Select an observed value from the full stream, independently of chart decimation.
    /// The coordinate is a presentation axis; samples without that axis are skipped.
    public func nearestPoint(to selection: Double, coordinate: (Date) -> Double?) -> MetricPoint? {
        guard selection.isFinite else { return nil }
        var nearest: MetricPoint?
        var separation = Double.infinity
        for point in points {
            guard let position = coordinate(point.timestamp), position.isFinite else { continue }
            let distance = abs(position - selection)
            if distance < separation {
                nearest = point
                separation = distance
            }
        }
        return nearest
    }

    /// Bound overview rendering while retaining original samples for all data operations.
    /// Each bucket contributes its extrema in timestamp order, including zero troughs.
    public var chartPoints: [MetricPoint] {
        let limit = 600
        guard points.count > limit else { return points }
        let buckets = (limit - 2) / 2
        let interiorCount = points.count - 2
        var result = [points[0]]
        result.reserveCapacity(limit)
        for bucket in 0..<buckets {
            let start = 1 + bucket * interiorCount / buckets
            let end = 1 + (bucket + 1) * interiorCount / buckets
            var low = start
            var high = start
            for index in start..<end {
                if points[index].value < points[low].value { low = index }
                if points[index].value > points[high].value { high = index }
            }
            result.append(points[min(low, high)])
            if low != high { result.append(points[max(low, high)]) }
        }
        result.append(points[points.count - 1])
        return result
    }
}

public extension Components.Schemas.SportSummary {
    var sportKind: HealthSport {
        switch self { case .case1: .cycling; case .case2: .running }
    }
    var recordedCommonSummary: Components.Schemas.CommonSummary {
        switch self {
        case .case1(let sport): sport.data.recordedSummary.cyclingCommonSummary
        case .case2(let sport): sport.data.recordedSummary.runningCommonSummary
        }
    }
}


public extension Workout {
    var sportKind: HealthSport {
        switch workoutObservation.observationSport { case .case1: .cycling; case .case2: .running }
    }
    var motion: Components.Schemas.MotionData {
        switch workoutObservation.observationSport {
        case .case1(let sport): sport.data.cyclingMotion
        case .case2(let sport): sport.data.runningMotion
        }
    }
    var recordedCommonSummary: Components.Schemas.CommonSummary {
        switch workoutObservation.observationSport {
        case .case1(let sport): sport.data.cyclingSummary.recordedSummary.cyclingCommonSummary
        case .case2(let sport): sport.data.runningSummary.recordedSummary.runningCommonSummary
        }
    }
    var calculatedCommonSummary: Components.Schemas.CommonSummary? {
        switch workoutObservation.observationSport {
        case .case1(let sport): sport.data.cyclingSummary.calculatedSummary?.calculationValue.cyclingCommonSummary
        case .case2(let sport): sport.data.runningSummary.calculatedSummary?.calculationValue.runningCommonSummary
        }
    }
    var metrics: [WorkoutMetric] {
        let data = motion
        var result = [
            WorkoutMetric(id: "heartRate", title: .heartRate, unit: "bpm", points: data.motionHeartRate.map { .init(timestamp: $0.timestamp, value: $0.value) }),
            WorkoutMetric(id: "power", title: .power, unit: "W", points: data.motionPower.map { .init(timestamp: $0.timestamp, value: $0.value) }),
            WorkoutMetric(id: "speed", title: .speed, unit: "km/h", points: data.motionSpeed.map { .init(timestamp: $0.timestamp, value: $0.value * 3.6) }),
            WorkoutMetric(id: "grade", title: .grade, unit: "%", points: data.motionGrade.map { .init(timestamp: $0.timestamp, value: $0.value) }),
            WorkoutMetric(id: "temperature", title: .temperature, unit: "°C", points: data.motionEnvironment.ambientTemperature.map { .init(timestamp: $0.timestamp, value: $0.value) }),
            WorkoutMetric(id: "altitude", title: .altitude, unit: "m", points: data.motionAltitude.map { .init(timestamp: $0.timestamp, value: $0.value) }),
        ]
        switch workoutObservation.observationSport {
        case .case1(let sport):
            result.append(.init(id: "cadence", title: .cyclingCadence, unit: "rpm", points: sport.data.cyclingCadence.map { .init(timestamp: $0.timestamp, value: $0.value) }))
        case .case2(let sport):
            result.append(.init(id: "cadence", title: .runningCadence, unit: "spm", points: sport.data.runningCadence.map { .init(timestamp: $0.timestamp, value: $0.value) }))
            let dynamics = sport.data.runningDynamics
            result.append(.init(id: "stepLength", title: .stepLength, unit: "m", points: dynamics.stepLength.map { .init(timestamp: $0.timestamp, value: $0.value) }))
            result.append(.init(id: "verticalOscillation", title: .verticalOscillation, unit: "cm", points: dynamics.verticalOscillation.map { .init(timestamp: $0.timestamp, value: $0.value * 100) }))
            result.append(.init(id: "groundContactTime", title: .groundContactTime, unit: "ms", points: dynamics.groundContactTime.map { .init(timestamp: $0.timestamp, value: $0.value * 1000) }))
        }
        return result
    }
}

public extension WorkoutMetric {
    /// Presentation conversion only; the backend owns statistics in canonical units.
    var canonicalScale: Double {
        switch id { case "speed": 3.6; case "verticalOscillation": 100; case "groundContactTime": 1000; default: 1 }
    }

    var fractionDigits: Int { ["speed", "stepLength", "verticalOscillation", "grade", "temperature"].contains(id) ? 1 : 0 }

    func displayValue(_ canonical: Double?) -> String {
        WorkoutFormat.number(canonical.map { $0 * canonicalScale }, unit: unit, fractionDigits: fractionDigits)
    }
}

public enum WorkoutFormat {
    public static func number(_ value: Double?, unit: String, fractionDigits: Int = 0, missing: String = "—") -> String {
        guard let value, value.isFinite else { return missing }
        return value.formatted(.number.precision(.fractionLength(fractionDigits))) + (unit.isEmpty ? "" : " " + unit)
    }
    public static func distance(_ metres: Double?, missing: String = "—") -> String { number(metres.map { $0 / 1000 }, unit: "km", fractionDigits: 2, missing: missing) }
    public static func duration(_ seconds: Double?, missing: String = "—") -> String {
        guard let seconds, seconds.isFinite, seconds >= 0, seconds < Double(Int.max) else { return missing }
        let total = Int(seconds.rounded(.down))
        return "\(total / 3600):" + String(format: "%02d:%02d", total / 60 % 60, total % 60)
    }
    public static func pace(_ metresPerSecond: Double?, missing: String = "—") -> String {
        guard let speed = metresPerSecond, speed.isFinite, speed > 0 else { return missing }
        let seconds = 1000 / speed
        guard seconds.rounded() < Double(Int.max) else { return missing }
        let total = Int(seconds.rounded())
        return "\(total / 60):" + String(format: "%02d /km", total % 60)
    }
}

public enum MetricLabel: Sendable { case heartRate, power, speed, grade, temperature, altitude, cyclingCadence, runningCadence, stepLength, verticalOscillation, groundContactTime }
