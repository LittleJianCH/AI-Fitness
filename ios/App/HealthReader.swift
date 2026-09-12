import ContractClient
import FitnessCore
import Foundation
import HealthKit

struct HealthWorkoutChoice: Identifiable, Sendable {
    let id: UUID
    let start: Date
    let end: Date
    let duration: Double
    let sport: HealthSport
}

// Each operation owns its HealthKit objects off the UI actor and returns only
// Sendable values. No framework query result is retained in UI state.
struct HealthReader: Sendable {
    private var quantityIDs: [HKQuantityTypeIdentifier] { [
        .heartRate, .cyclingPower, .cyclingSpeed, .cyclingCadence, .runningPower, .runningSpeed,
        .distanceCycling, .distanceWalkingRunning, .activeEnergyBurned,
        .runningStrideLength, .runningVerticalOscillation, .runningGroundContactTime,
    ] }

    func authorize() async throws {
        let store = HKHealthStore()
        guard HKHealthStore.isHealthDataAvailable() else { throw HealthImportError.unavailable }
        var types: Set<HKObjectType> = [HKObjectType.workoutType(), HKSeriesType.workoutRoute()]
        for id in quantityIDs { if let type = HKObjectType.quantityType(forIdentifier: id) { types.insert(type) } }
        try await store.requestAuthorization(toShare: [], read: types)
    }

    func workouts(from: Date, to: Date) async throws -> [HealthWorkoutChoice] {
        let store = HKHealthStore()
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForSamples(withStart: from, end: to, options: [.strictStartDate, .strictEndDate]),
            NSCompoundPredicate(orPredicateWithSubpredicates: [HKQuery.predicateForWorkouts(with: .cycling), HKQuery.predicateForWorkouts(with: .running)]),
        ])
        let results = try await HKSampleQueryDescriptor(predicates: [.workout(predicate)],
                                                       sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)], limit: 200).result(for: store)
        try Task.checkCancellation()
        return results.compactMap { workout in
            guard !isOwnExport(workout), let sport = supportedSport(workout) else { return nil }
            return .init(id: workout.uuid, start: workout.startDate, end: workout.endDate, duration: workout.duration, sport: sport)
        }
    }

    func preview(id: UUID) async throws -> HealthImportPreview {
        let store = HKHealthStore()
        let results = try await HKSampleQueryDescriptor(predicates: [.workout(HKQuery.predicateForObject(with: id))],
                                                       sortDescriptors: [], limit: 1).result(for: store)
        guard let workout = results.first, !isOwnExport(workout) else { throw HealthImportError.missingWorkout }
        guard let sport = supportedSport(workout) else { throw HealthImportError.unsupportedWorkout }
        var input = HealthObservationInput(objectID: workout.uuid, sport: sport, start: workout.startDate,
                                           end: workout.endDate, timerDuration: workout.duration)
        let source = workout.sourceRevision
        input.sourceDescription = "\(source.source.name) · \(source.source.bundleIdentifier) · \(source.version ?? "unknown")"
        let distanceID: HKQuantityTypeIdentifier = sport == .cycling ? .distanceCycling : .distanceWalkingRunning
        let powerID: HKQuantityTypeIdentifier = sport == .cycling ? .cyclingPower : .runningPower
        let speedID: HKQuantityTypeIdentifier = sport == .cycling ? .cyclingSpeed : .runningSpeed
        input.summary.summaryDistance = statistics(workout, distanceID)?.sumQuantity()?.doubleValue(for: .meter())
        input.summary.summaryMetabolicEnergy = statistics(workout, .activeEnergyBurned)?.sumQuantity()?.doubleValue(for: .joule())
        let hr = statistics(workout, .heartRate), power = statistics(workout, powerID), speed = statistics(workout, speedID)
        let bpm = HKUnit.count().unitDivided(by: .minute()), metresPerSecond = HKUnit.meter().unitDivided(by: .second())
        input.summary.summaryHeartRate = .init(averageValue: hr?.averageQuantity()?.doubleValue(for: bpm),
                                               maximumValue: hr?.maximumQuantity()?.doubleValue(for: bpm),
                                               minimumValue: hr?.minimumQuantity()?.doubleValue(for: bpm))
        input.summary.summaryPower = .init(averageValue: power?.averageQuantity()?.doubleValue(for: .watt()),
                                           maximumValue: power?.maximumQuantity()?.doubleValue(for: .watt()),
                                           minimumValue: power?.minimumQuantity()?.doubleValue(for: .watt()))
        input.summary.summarySpeed = .init(averageValue: speed?.averageQuantity()?.doubleValue(for: metresPerSecond),
                                           maximumValue: speed?.maximumQuantity()?.doubleValue(for: metresPerSecond),
                                           minimumValue: speed?.minimumQuantity()?.doubleValue(for: metresPerSecond))
        input.heartRate = try await samples(.heartRate, unit: bpm, workout: workout, store: store)
        input.power = try await samples(powerID, unit: .watt(), workout: workout, store: store)
        input.speed = try await samples(speedID, unit: metresPerSecond, workout: workout, store: store)
        input.distance = try await samples(distanceID, unit: .meter(), workout: workout, store: store)
        input.energy = try await samples(.activeEnergyBurned, unit: .joule(), workout: workout, store: store)
        if sport == .cycling {
            input.cyclingCadence = try await samples(.cyclingCadence, unit: bpm, workout: workout, store: store)
        } else {
            input.stepLength = try await samples(.runningStrideLength, unit: .meter(), workout: workout, store: store)
            input.verticalOscillation = try await samples(.runningVerticalOscillation, unit: .meter(), workout: workout, store: store)
            input.groundContactTime = try await samples(.runningGroundContactTime, unit: .second(), workout: workout, store: store)
        }
        let routes = try await HKSampleQueryDescriptor(predicates: [.workoutRoute(associated(workout))],
                                                      sortDescriptors: [SortDescriptor(\.startDate)], limit: 1_001).result(for: store)
        guard routes.count <= 1_000 else { throw HealthImportError.tooManySamples }
        for route in routes {
            for try await location in HKWorkoutRouteQueryDescriptor(route).results(for: store) {
                try Task.checkCancellation()
                guard location.horizontalAccuracy >= 0 else { continue }
                input.locations.append(.init(timestamp: location.timestamp, latitude: location.coordinate.latitude,
                                             longitude: location.coordinate.longitude,
                                             altitude: location.verticalAccuracy >= 0 ? location.altitude : nil))
                guard input.locations.count <= 50_000 else { throw HealthImportError.tooManySamples }
            }
        }
        for event in workout.workoutEvents ?? [] {
            switch event.type {
            case .pause:
                input.events.append(.init(timestamp: event.dateInterval.start, value: .case2(.init(_type: .timerStopped))))
            case .resume:
                input.events.append(.init(timestamp: event.dateInterval.start, value: .case1(.init(_type: .timerStarted))))
            default:
                input.events.append(.init(timestamp: event.dateInterval.start, value: .case6(.init(
                    eventDetail: "Interval end: " + event.dateInterval.end.ISO8601Format(),
                    eventName: "healthkit.event.\(event.type.rawValue)", _type: .otherEvent))))
            }
        }
        input.events.sort { $0.timestamp < $1.timestamp }
        try Task.checkCancellation()
        return try input.preview()
    }

    private func samples(_ id: HKQuantityTypeIdentifier, unit: HKUnit, workout: HKWorkout, store: HKHealthStore) async throws -> [HealthQuantitySample] {
        guard let type = HKObjectType.quantityType(forIdentifier: id) else { return [] }
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            associated(workout),
            HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate, options: [.strictStartDate, .strictEndDate]),
        ])
        let samples = try await HKSampleQueryDescriptor(predicates: [.quantitySample(type: type, predicate: predicate)],
                                                       sortDescriptors: [SortDescriptor(\.endDate)], limit: 50_001).result(for: store)
        try Task.checkCancellation()
        guard samples.count <= 50_000 else { throw HealthImportError.tooManySamples }
        return samples.map { .init(start: $0.startDate, end: $0.endDate, value: $0.quantity.doubleValue(for: unit)) }
    }

    private func associated(_ workout: HKWorkout) -> NSPredicate {
        NSCompoundPredicate(andPredicateWithSubpredicates: [HKQuery.predicateForObjects(from: workout),
                                                           HKQuery.predicateForObjects(from: workout.sourceRevision.source)])
    }

    private func statistics(_ workout: HKWorkout, _ id: HKQuantityTypeIdentifier) -> HKStatistics? {
        HKObjectType.quantityType(forIdentifier: id).flatMap { workout.statistics(for: $0) }
    }

    private func isOwnExport(_ workout: HKWorkout) -> Bool {
        workout.sourceRevision.source.bundleIdentifier == Bundle.main.bundleIdentifier
            || workout.metadata?["com.aifitness.export.identity"] != nil
    }

    private func supportedSport(_ workout: HKWorkout) -> HealthSport? {
        guard workout.workoutActivities.allSatisfy({ $0.workoutConfiguration.activityType == workout.workoutActivityType }) else { return nil }
        switch workout.workoutActivityType { case .cycling: return .cycling; case .running: return .running; default: return nil }
    }
}
