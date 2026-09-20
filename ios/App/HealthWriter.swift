import CoreLocation
import FitnessCore
import HealthKit

/// Framework objects remain local to asynchronous operations, outside the UI actor.
struct HealthWriter: HealthExportWriter {
    static let identityKey = "com.aifitness.export.identity"

    func authorize(plan: HealthExportPlan) async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw HealthImportError.unavailable }
        let store = HKHealthStore()
        let types = try sampleTypes(plan)
        try await store.requestAuthorization(toShare: types, read: Set(types.map { $0 as HKObjectType }))
        guard types.allSatisfy({ store.authorizationStatus(for: $0) == .sharingAuthorized }) else {
            throw HealthWriterError.permission
        }
    }

    func createWorkout(plan: HealthExportPlan, beforeCommit: @Sendable () async throws -> Void) async throws -> UUID? {
        let store = HKHealthStore()
        let configuration = HKWorkoutConfiguration()
        switch plan.workout.workoutObservation.observationSport {
        case .case1: configuration.activityType = .cycling
        case .case2: configuration.activityType = .running
        }
        configuration.locationType = .unknown
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: nil)
        let range = plan.workout.workoutObservation.observationRange
        do {
            try await builder.beginCollection(at: range.rangeStart)
            try await builder.addMetadata(metadata(plan.identity))
            let quantities = try plan.quantities()
            var existing: [String: HKQuantitySample] = [:]
            for kind in Set(quantities.map(\.kind)) {
                let (type, _) = try quantity(kind)
                let ids = quantities.enumerated().filter { $0.element.kind == kind }.map { plan.identity + "/sample/\($0.offset)" }
                let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                    HKQuery.predicateForObjects(from: HKSource.default()),
                    HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeySyncIdentifier, allowedValues: ids),
                ])
                let stored = try await HKSampleQueryDescriptor(predicates: [.quantitySample(type: type, predicate: predicate)], sortDescriptors: [], limit: 50_001).result(for: store)
                for sample in stored {
                    if let key = sample.metadata?[HKMetadataKeySyncIdentifier] as? String {
                        guard existing[key] == nil else { throw HealthExportError.uncertainWorkout }
                        existing[key] = sample
                    }
                }
            }
            let samples = try quantities.enumerated().map { index, value -> HKQuantitySample in
                let (type, unit) = try quantity(value.kind)
                let key = plan.identity + "/sample/\(index)"
                if let sample = existing[key] { return sample }
                return HKQuantitySample(type: type, quantity: HKQuantity(unit: unit, doubleValue: value.value),
                                        start: value.start, end: value.end, metadata: metadata(key))
            }
            if !samples.isEmpty { try await builder.addSamples(samples) }
            let events = plan.workout.workoutObservation.observationEvents.compactMap { event -> HKWorkoutEvent? in
                let type: HKWorkoutEventType
                switch event.value {
                case .case1: type = .resume
                case .case2: type = .pause
                default: return nil
                }
                return HKWorkoutEvent(type: type, dateInterval: DateInterval(start: event.timestamp, duration: 0), metadata: nil)
            }
            if !events.isEmpty { try await builder.addWorkoutEvents(events) }
            try Task.checkCancellation()
            try await builder.endCollection(at: range.rangeEnd)
            try await beforeCommit()
        } catch {
            builder.discardWorkout()
            throw error
        }
        // nil without error can mean a successful save while the device is locked.
        guard try await builder.finishWorkout() != nil else { return nil }
        return try await findWorkout(plan: plan)
    }

    func findWorkout(plan: HealthExportPlan) async throws -> UUID? {
        let store = HKHealthStore()
        let predicate = ownIdentity(plan.identity)
        let workouts = try await HKSampleQueryDescriptor(predicates: [.workout(predicate)], sortDescriptors: [], limit: 2).result(for: store)
        guard workouts.count == 1, let workout = workouts.first else { return nil }
        // An interrupted finish is acknowledged only after its associated quantities exist.
        let expected = try plan.quantities()
        for kind in Set(expected.map(\.kind)) {
            let (type, _) = try quantity(kind)
            let samples = try await HKSampleQueryDescriptor(predicates: [.quantitySample(type: type, predicate:
                HKQuery.predicateForObjects(from: workout))], sortDescriptors: [], limit: 50_001).result(for: store)
            let identifiers = Set(samples.compactMap { $0.metadata?[HKMetadataKeySyncIdentifier] as? String })
            for (index, value) in expected.enumerated() where value.kind == kind {
                guard identifiers.contains(plan.identity + "/sample/\(index)") else { return nil }
            }
        }
        return workout.uuid
    }

    func createRoute(plan: HealthExportPlan, workoutID: UUID, beforeCommit: @Sendable () async throws -> Void) async throws {
        let store = HKHealthStore()
        let workouts = try await HKSampleQueryDescriptor(predicates: [.workout(HKQuery.predicateForObject(with: workoutID))], sortDescriptors: [], limit: 1).result(for: store)
        guard let workout = workouts.first else { throw HealthExportError.uncertainWorkout }
        // The workout is already committed; this separate builder owns only its route.
        let builder = HKWorkoutRouteBuilder(healthStore: store, device: nil)
        let locations = try routeLocations(plan)
        for offset in stride(from: 0, to: locations.count, by: 1_000) {
            try Task.checkCancellation()
            try await builder.insertRouteData(Array(locations[offset..<min(offset + 1_000, locations.count)]))
        }
        try await beforeCommit()
        _ = try await builder.finishRoute(with: workout, metadata: metadata(plan.identity + "/route"))
        guard try await findRoute(plan: plan, workoutID: workoutID) else { throw HealthExportError.uncertainRoute }
    }

    func findRoute(plan: HealthExportPlan, workoutID: UUID) async throws -> Bool {
        let store = HKHealthStore()
        let routes = try await HKSampleQueryDescriptor(predicates: [.workoutRoute(ownIdentity(plan.identity + "/route"))], sortDescriptors: [], limit: 2).result(for: store)
        guard routes.count == 1, let route = routes.first else { return false }
        let workouts = try await HKSampleQueryDescriptor(predicates: [.workout(HKQuery.predicateForObject(with: workoutID))], sortDescriptors: [], limit: 1).result(for: store)
        guard let workout = workouts.first else { return false }
        let associated = try await HKSampleQueryDescriptor(predicates: [.workoutRoute(HKQuery.predicateForObjects(from: workout))], sortDescriptors: [], limit: 1_001).result(for: store)
        guard associated.contains(where: { $0.uuid == route.uuid }) else { return false }
        let expected = plan.workout.motion.motionPosition
        var index = 0
        for try await location in HKWorkoutRouteQueryDescriptor(route).results(for: store) {
            guard index < expected.count else { return false }
            let value = expected[index]
            guard abs(location.timestamp.timeIntervalSince(value.timestamp)) < 0.001,
                  abs(location.coordinate.latitude - value.value.latitude) < 0.0000001,
                  abs(location.coordinate.longitude - value.value.longitude) < 0.0000001 else { return false }
            index += 1
        }
        return index == expected.count
    }

    private func routeLocations(_ plan: HealthExportPlan) throws -> [CLLocation] {
        let range = plan.workout.workoutObservation.observationRange
        return try plan.workout.motion.motionPosition.map { point in
            let coordinate = CLLocationCoordinate2D(latitude: point.value.latitude, longitude: point.value.longitude)
            guard CLLocationCoordinate2DIsValid(coordinate), point.timestamp >= range.rangeStart, point.timestamp <= range.rangeEnd else {
                throw HealthExportError.invalidData
            }
            // Unknown accuracies use Core Location's invalid sentinel; no accuracy is invented.
            return CLLocation(coordinate: coordinate, altitude: 0, horizontalAccuracy: -1, verticalAccuracy: -1, timestamp: point.timestamp)
        }
    }

    private func metadata(_ identity: String) -> [String: Any] {
        [Self.identityKey: identity, HKMetadataKeySyncIdentifier: identity, HKMetadataKeySyncVersion: 1]
    }
    private func ownIdentity(_ identity: String) -> NSPredicate {
        NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForObjects(from: HKSource.default()),
            HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeySyncIdentifier, allowedValues: [identity]),
        ])
    }
    private func sampleTypes(_ plan: HealthExportPlan) throws -> Set<HKSampleType> {
        var types: Set<HKSampleType> = [HKObjectType.workoutType()]
        for value in try plan.quantities() { types.insert(try quantity(value.kind).0) }
        if !plan.workout.motion.motionPosition.isEmpty { types.insert(HKSeriesType.workoutRoute()) }
        return types
    }
    private func quantity(_ kind: HealthExportQuantityKind) throws -> (HKQuantityType, HKUnit) {
        let id: HKQuantityTypeIdentifier
        let unit: HKUnit
        switch kind {
        case .heartRate: id = .heartRate; unit = .count().unitDivided(by: .minute())
        case .cyclingCadence: id = .cyclingCadence; unit = .count().unitDivided(by: .minute())
        case .cyclingPower: id = .cyclingPower; unit = .watt()
        case .runningPower: id = .runningPower; unit = .watt()
        case .cyclingSpeed: id = .cyclingSpeed; unit = .meter().unitDivided(by: .second())
        case .runningSpeed: id = .runningSpeed; unit = .meter().unitDivided(by: .second())
        case .distanceCycling: id = .distanceCycling; unit = .meter()
        case .distanceWalkingRunning: id = .distanceWalkingRunning; unit = .meter()
        case .activeEnergyBurned: id = .activeEnergyBurned; unit = .joule()
        case .runningStrideLength: id = .runningStrideLength; unit = .meter()
        case .runningVerticalOscillation: id = .runningVerticalOscillation; unit = .meter()
        case .runningGroundContactTime: id = .runningGroundContactTime; unit = .second()
        }
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { throw HealthExportError.invalidData }
        return (type, unit)
    }
}

enum HealthWriterError: Error {
    case permission
    var resource: LocalizedStringResource { "Allow writing the previewed data types in Health permissions." }
}
