import Charts
import FitnessCore
import SwiftUI

@MainActor
struct PowerCurveSection: View {
    let workout: Workout
    let refreshWorkout: () -> Void
    @State private var store: PowerCurveStore
    @State private var selectedDuration = 60
    @State private var reload = 0

    init(workout: Workout, api: FitnessAPI, session: SessionStore, refreshWorkout: @escaping () -> Void) {
        self.workout = workout
        self.refreshWorkout = refreshWorkout
        _store = State(initialValue: PowerCurveStore(service: api, session: session))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            FitnessSectionTitle(title: "Best sustained power", color: .purple)
                .accessibilityIdentifier("powerCurve")
            VStack(alignment: .leading, spacing: 18) {
                if workout.motion.motionPower.isEmpty {
                    Text("There are not enough continuous power samples to calculate best sustained power.")
                } else if store.isLoading {
                    ProgressView("Calculating best sustained power…")
                } else if store.needsWorkoutRefresh {
                    Text("The workout has changed. Refresh to view its current power curve.")
                    Button("Refresh workout", action: refreshWorkout)
                } else if let message = store.message {
                    IssueText(message).foregroundStyle(.secondary)
                    Button("Retry") { reload += 1 }.buttonStyle(.bordered)
                } else if let curve = store.curve {
                    results(curve)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(20).fitnessCard()
            if let curve = store.curve {
                Text("Single workout · W · Includes recorded zeros. Samples up to \(curve.maxGapSeconds) seconds apart are linearly interpolated; longer gaps break the interval without zero filling or extrapolation. Duration uses a logarithmic axis and connecting lines are reading guides. Interval times are relative to workout start.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .task(id: "\(workout.workoutId)/\(workout.workoutRevision)/\(reload)") {
            if !workout.motion.motionPower.isEmpty {
                await store.load(id: workout.workoutId, revision: workout.workoutRevision)
            }
        }
    }

    @ViewBuilder
    private func results(_ curve: PowerCurve) -> some View {
        let available = curve.points.filter { $0.best != nil }
        let selected = available.first { $0.durationSeconds == selectedDuration } ?? available.first
        if let selected, let effort = selected.best {
            Chart(available, id: \.durationSeconds) { point in
                if let best = point.best {
                    LineMark(x: .value("Duration in seconds", Double(point.durationSeconds)), y: .value("W", best.averagePower))
                        .foregroundStyle(.purple).interpolationMethod(.linear)
                    PointMark(x: .value("Duration in seconds", Double(point.durationSeconds)), y: .value("W", best.averagePower))
                        .foregroundStyle(.purple).symbolSize(point.durationSeconds == selected.durationSeconds ? 70 : 20)
                }
            }
            .chartXScale(domain: 1...Double(max(5, available.last?.durationSeconds ?? 5)), type: .log)
            .chartXAxis {
                AxisMarks(values: [1.0, 10, 60, 600, 3600, 14400]) { value in
                    AxisGridLine()
                    AxisValueLabel { if let seconds = value.as(Double.self) { Text(WorkoutFormat.duration(seconds)) } }
                }
            }
            .chartYScale(domain: .automatic(includesZero: true))
            .frame(height: 240)
            .accessibilityLabel("Best sustained power chart. Use the duration picker or data list to inspect values.")
            Text("\(WorkoutFormat.duration(Double(selected.durationSeconds))) · \(WorkoutFormat.number(effort.averagePower, unit: "W", fractionDigits: 1))")
                .font(.title2.bold()).monospacedDigit().foregroundStyle(.purple)
                .accessibilityIdentifier("powerCurveSelected")
            Text("Best interval: \(offset(effort.start)) – \(offset(effort.end))").font(.subheadline).foregroundStyle(.secondary)
            Picker("Effort duration", selection: Binding(get: { selected.durationSeconds }, set: { selectedDuration = $0 })) {
                ForEach(available, id: \.durationSeconds) { point in
                    Text(WorkoutFormat.duration(Double(point.durationSeconds))).tag(point.durationSeconds)
                }
            }.accessibilityIdentifier("powerCurveDuration")
        } else {
            Text("There are not enough continuous power samples to calculate best sustained power.")
        }
        DisclosureGroup("View best power data") {
            ForEach(curve.points, id: \.durationSeconds) { point in
                VStack(alignment: .leading, spacing: 5) {
                    Text(WorkoutFormat.duration(Double(point.durationSeconds))).font(.headline)
                    if let best = point.best {
                        Text(WorkoutFormat.number(best.averagePower, unit: "W", fractionDigits: 1))
                        Text("\(offset(best.start)) – \(offset(best.end))").foregroundStyle(.secondary)
                    } else { Text("Insufficient continuous samples").foregroundStyle(.secondary) }
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func offset(_ date: Date) -> String {
        WorkoutFormat.duration(date.timeIntervalSince(workout.workoutObservation.observationRange.rangeStart))
    }
}
