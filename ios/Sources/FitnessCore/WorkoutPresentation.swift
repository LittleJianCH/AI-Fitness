import ContractClient
import Foundation

public struct MetricPoint: Identifiable, Sendable {
    public var id: Date { timestamp }
    public let timestamp: Date
    public let value: Double
}

public struct WorkoutMetric: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let unit: String
    public let points: [MetricPoint]

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
    var sportName: String {
        switch self { case .case1: "骑行"; case .case2: "跑步" }
    }
    var recordedCommonSummary: Components.Schemas.CommonSummary {
        switch self {
        case .case1(let sport): sport.data.recordedSummary.cyclingCommonSummary
        case .case2(let sport): sport.data.recordedSummary.runningCommonSummary
        }
    }
}

public extension WorkoutCard {
    var displayTitle: String { userData.workoutTitle ?? summary.sportName }
}

public extension Workout {
    var sportName: String {
        switch workoutObservation.observationSport { case .case1: "骑行"; case .case2: "跑步" }
    }
    var displayTitle: String { workoutUserData.workoutTitle ?? sportName }
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
            WorkoutMetric(id: "heartRate", title: "心率", unit: "bpm", points: data.motionHeartRate.map { .init(timestamp: $0.timestamp, value: $0.value) }),
            WorkoutMetric(id: "power", title: "功率", unit: "W", points: data.motionPower.map { .init(timestamp: $0.timestamp, value: $0.value) }),
            WorkoutMetric(id: "speed", title: "速度", unit: "km/h", points: data.motionSpeed.map { .init(timestamp: $0.timestamp, value: $0.value * 3.6) }),
            WorkoutMetric(id: "altitude", title: "海拔", unit: "m", points: data.motionAltitude.map { .init(timestamp: $0.timestamp, value: $0.value) }),
        ]
        switch workoutObservation.observationSport {
        case .case1(let sport):
            result.append(.init(id: "cadence", title: "踏频", unit: "rpm", points: sport.data.cyclingCadence.map { .init(timestamp: $0.timestamp, value: $0.value) }))
        case .case2(let sport):
            result.append(.init(id: "cadence", title: "步频", unit: "步/分", points: sport.data.runningCadence.map { .init(timestamp: $0.timestamp, value: $0.value) }))
        }
        return result
    }
}

public enum WorkoutFormat {
    public static func number(_ value: Double?, unit: String, fractionDigits: Int = 0) -> String {
        guard let value, value.isFinite else { return "无数据" }
        return value.formatted(.number.precision(.fractionLength(fractionDigits))) + " " + unit
    }
    public static func distance(_ metres: Double?) -> String { number(metres.map { $0 / 1000 }, unit: "km", fractionDigits: 2) }
    public static func duration(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0, seconds < Double(Int.max) else { return "无数据" }
        let total = Int(seconds.rounded(.down))
        return "\(total / 3600):" + String(format: "%02d:%02d", total / 60 % 60, total % 60)
    }
    public static func pace(_ metresPerSecond: Double?) -> String {
        guard let speed = metresPerSecond, speed.isFinite, speed > 0 else { return "无数据" }
        let seconds = 1000 / speed
        guard seconds.rounded() < Double(Int.max) else { return "无数据" }
        let total = Int(seconds.rounded())
        return "\(total / 60):" + String(format: "%02d /km", total % 60)
    }
}
