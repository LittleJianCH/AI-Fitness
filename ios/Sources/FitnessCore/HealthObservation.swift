import ContractClient
import Foundation

public enum HealthSport: String, Sendable { case cycling, running }

/// HealthKit interval values after conversion to canonical units by the adapter.
public struct HealthQuantitySample: Sendable {
    public let start: Date
    public let end: Date
    public let value: Double
    public init(start: Date, end: Date, value: Double) {
        self.start = start; self.end = end; self.value = value
    }
}

public struct HealthLocation: Sendable {
    public let timestamp: Date
    public let latitude: Double
    public let longitude: Double
    public let altitude: Double?
    public init(timestamp: Date, latitude: Double, longitude: Double, altitude: Double?) {
        self.timestamp = timestamp; self.latitude = latitude; self.longitude = longitude; self.altitude = altitude
    }
}

public enum HealthImportError: Error, Equatable, Sendable {
    case unavailable, unsupportedWorkout, ambiguousSamples, tooManySamples, missingWorkout, invalidAcknowledgement

}

public struct HealthImportPreview: Identifiable, Sendable {
    public let id: String
    public let observation: Components.Schemas.WorkoutObservation
    public let sampleCount: Int

    public var summary: Components.Schemas.CommonSummary {
        switch observation.observationSport {
        case .case1(let sport): sport.data.cyclingSummary.recordedSummary.cyclingCommonSummary
        case .case2(let sport): sport.data.runningSummary.recordedSummary.runningCommonSummary
        }
    }
    public var motion: Components.Schemas.MotionData {
        switch observation.observationSport {
        case .case1(let sport): sport.data.cyclingMotion
        case .case2(let sport): sport.data.runningMotion
        }
    }
    public var isRunning: Bool {
        if case .case2 = observation.observationSport { return true }
        return false
    }

    public var submission: Components.Schemas.HealthKitSubmission {
        .init(expectedWorkouts: [], intent: .normal, objectId: id, parts: [
            .init(initialUserData: .init(statisticsInclusion: .includeInStatistics, workoutTags: []),
                  observation: observation, partKey: "workout")
        ])
    }
}

/// The input contains one workout's own associated source streams. It is not a
/// cross-source reconciliation model. The backend still validates publication.
public struct HealthObservationInput: Sendable {
    public let objectID: UUID
    public let sport: HealthSport
    public let start: Date
    public let end: Date
    public var summary: Components.Schemas.CommonSummary
    public var sourceDescription = ""
    public var heartRate: [HealthQuantitySample] = []
    public var power: [HealthQuantitySample] = []
    public var speed: [HealthQuantitySample] = []
    public var cyclingCadence: [HealthQuantitySample] = []
    public var distance: [HealthQuantitySample] = []
    public var energy: [HealthQuantitySample] = []
    public var stepLength: [HealthQuantitySample] = []
    public var verticalOscillation: [HealthQuantitySample] = []
    public var groundContactTime: [HealthQuantitySample] = []
    public var locations: [HealthLocation] = []
    public var events: [Components.Schemas.Timed_WorkoutEvent] = []

    public init(objectID: UUID, sport: HealthSport, start: Date, end: Date, timerDuration: Double) {
        self.objectID = objectID; self.sport = sport; self.start = start; self.end = end
        summary = .init(summaryAltitude: .init(), summaryElapsedTime: end.timeIntervalSince(start),
                        summaryGrade: .init(), summaryHeartRate: .init(), summaryPower: .init(),
                        summarySpeed: .init(), summaryTemperature: .init(), summaryTimerTime: timerDuration)
    }

    public func preview() throws -> HealthImportPreview {
        let hr = try points(heartRate), watts = try points(power), velocity = try points(speed)
        let cadence = try points(cyclingCadence), metres = try points(distance, cumulative: true)
        let joules = try points(energy, cumulative: true), stride = try points(stepLength)
        let oscillation = try points(verticalOscillation), contact = try points(groundContactTime)
        let route = locations.sorted { $0.timestamp < $1.timestamp }
        guard start < end, route.allSatisfy({ start <= $0.timestamp && $0.timestamp <= end }),
              zip(route, route.dropFirst()).allSatisfy({ $0.timestamp < $1.timestamp }) else {
            throw HealthImportError.ambiguousSamples
        }
        let motion = Components.Schemas.MotionData(
            motionAltitude: route.compactMap { point in point.altitude.map { .init(timestamp: point.timestamp, value: $0) } },
            motionDistance: metres.map { .init(timestamp: $0.end, value: $0.value) },
            motionEnergy: joules.map { .init(timestamp: $0.end, value: $0.value) },
            motionEnvironment: .init(ambientTemperature: [], relativeHumidity: [], windFrom: [], windSpeed: []),
            motionGrade: [], motionHeartRate: hr.map { .init(timestamp: $0.end, value: $0.value) },
            motionPosition: route.map { .init(timestamp: $0.timestamp, value: .init(latitude: $0.latitude, longitude: $0.longitude)) },
            motionPower: watts.map { .init(timestamp: $0.end, value: $0.value) },
            motionSpeed: velocity.map { .init(timestamp: $0.end, value: $0.value) }
        )
        let canonicalSport: Components.Schemas.Sport
        switch sport {
        case .cycling:
            canonicalSport = .case1(.init(data: .init(
                cyclingCadence: cadence.map { .init(timestamp: $0.end, value: $0.value) },
                cyclingContext: .init(), cyclingGearChanges: [], cyclingLaps: [], cyclingMotion: motion,
                cyclingPedaling: .init(leftPowerShare: [], leftSmoothness: [], leftTorqueEffectiveness: [], rightSmoothness: [], rightTorqueEffectiveness: []),
                cyclingSummary: .init(recordedSummary: .init(cyclingCommonSummary: summary, summaryCyclingCadence: .init()))
            ), _type: .cycling))
        case .running:
            canonicalSport = .case2(.init(data: .init(
                runningCadence: [],
                runningDynamics: .init(groundContactTime: contact.map { .init(timestamp: $0.end, value: $0.value) },
                                       stepLength: stride.map { .init(timestamp: $0.end, value: $0.value) },
                                       verticalOscillation: oscillation.map { .init(timestamp: $0.end, value: $0.value) }),
                runningLaps: [], runningMotion: motion,
                runningSummary: .init(recordedSummary: .init(runningCommonSummary: summary, summaryGroundContactTime: .init(),
                                                            summaryRunningCadence: .init(), summaryStepLength: .init(), summaryVerticalOscillation: .init()))
            ), _type: .running))
        }
        let count = hr.count + watts.count + velocity.count + cadence.count + metres.count + joules.count + stride.count + oscillation.count + contact.count + route.count
        guard count <= 50_000 else { throw HealthImportError.tooManySamples }
        return .init(id: objectID.uuidString.lowercased(), observation: .init(
            observationAthlete: .init(), observationCoursePoints: [],
            observationDataIssues: [.init(issueDescription: "HealthKit projection: only readable, fully contained quantity samples associated with this workout and its source are included. Interval quantities are placed at interval end; cumulative distance/energy sum available non-overlapping increments. Route positions with invalid horizontal accuracy and altitudes with invalid vertical accuracy are omitted. Missing streams remain missing. Running cadence is not inferred from step counts.", issueField: "healthkit")],
            observationEvents: events,
            observationExtensions: [.init(extensionData: .case2(.init(textSamples: [], textSummary: sourceDescription, _type: .textExtension)),
                                          extensionKey: "healthkit.source", extensionLabel: "HealthKit source")],
            observationRange: .init(rangeEnd: end, rangeStart: start), observationSport: canonicalSport
        ), sampleCount: count)
    }

    private func points(_ values: [HealthQuantitySample], cumulative: Bool = false) throws -> [HealthQuantitySample] {
        let sorted = values.sorted { $0.end < $1.end }
        var result: [HealthQuantitySample] = []
        var previous: HealthQuantitySample?
        var total = 0.0
        for sample in sorted {
            guard sample.value.isFinite, start <= sample.start, sample.start <= sample.end, sample.end <= end,
                  previous.map({ $0.end < sample.end && (!cumulative || $0.end <= sample.start) }) ?? true else {
                throw HealthImportError.ambiguousSamples
            }
            total += sample.value
            guard !cumulative || total.isFinite else { throw HealthImportError.ambiguousSamples }
            result.append(.init(start: sample.start, end: sample.end, value: cumulative ? total : sample.value))
            previous = sample
        }
        return result
    }
}
