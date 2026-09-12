import ContractClient
import Foundation

public enum HealthExportQuantityKind: String, Sendable {
    case heartRate, cyclingPower, cyclingSpeed, cyclingCadence, runningPower, runningSpeed
    case distanceCycling, distanceWalkingRunning, activeEnergyBurned
    case runningStrideLength, runningVerticalOscillation, runningGroundContactTime
}

public struct HealthExportQuantity: Sendable {
    public let kind: HealthExportQuantityKind
    public let start: Date
    public let end: Date
    public let value: Double
}

public extension HealthExportPlan {
    /// Project recorded measurements only. Totals are not added to cumulative streams.
    func quantities() throws -> [HealthExportQuantity] {
        var result: [HealthExportQuantity] = []
        let range = workout.workoutObservation.observationRange
        let cycling: Bool
        switch workout.workoutObservation.observationSport { case .case1: cycling = true; case .case2: cycling = false }
        func append(_ kind: HealthExportQuantityKind, _ points: [(Date, Double)]) {
            result += points.map { .init(kind: kind, start: $0.0, end: $0.0, value: $0.1) }
        }
        let motion = workout.motion
        append(.heartRate, motion.motionHeartRate.map { ($0.timestamp, $0.value) })
        append(cycling ? .cyclingPower : .runningPower, motion.motionPower.map { ($0.timestamp, $0.value) })
        append(cycling ? .cyclingSpeed : .runningSpeed, motion.motionSpeed.map { ($0.timestamp, $0.value) })
        switch workout.workoutObservation.observationSport {
        case .case1(let sport):
            append(.cyclingCadence, sport.data.cyclingCadence.map { ($0.timestamp, $0.value) })
        case .case2(let sport):
            append(.runningStrideLength, sport.data.runningDynamics.stepLength.map { ($0.timestamp, $0.value) })
            append(.runningVerticalOscillation, sport.data.runningDynamics.verticalOscillation.map { ($0.timestamp, $0.value) })
            append(.runningGroundContactTime, sport.data.runningDynamics.groundContactTime.map { ($0.timestamp, $0.value) })
        }
        let summary = workout.recordedCommonSummary
        if let distance = summary.summaryDistance {
            result.append(.init(kind: cycling ? .distanceCycling : .distanceWalkingRunning, start: range.rangeStart, end: range.rangeEnd, value: distance))
        }
        if let energy = summary.summaryMetabolicEnergy {
            result.append(.init(kind: .activeEnergyBurned, start: range.rangeStart, end: range.rangeEnd, value: energy))
        }
        guard result.count <= 50_000,
              result.allSatisfy({ $0.value.isFinite && $0.value >= 0 && $0.start >= range.rangeStart && $0.end <= range.rangeEnd }) else {
            throw HealthExportError.invalidData
        }
        return result
    }

    static var projectionNotice: String {
        "导出骑行/跑步、记录中的心率/功率/速度等支持的采样，以及路线经纬度。距离和能量使用记录总量，不重复叠加累计曲线；缺失总量不推算。Apple 健康会按起止时间和暂停事件计算时长，可能与记录摘要不同。路线精度未知，不伪造定位精度；海拔不写入。圈、跑步步频、备注、标签、后端计算摘要及其他不支持的字段不写入。这是平台副本，不是完整备份；新版本会生成新的副本。"
    }
}
