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
            FitnessSectionTitle(title: "最佳持续功率", color: .purple)
                .accessibilityIdentifier("powerCurve")
            VStack(alignment: .leading, spacing: 18) {
                if workout.motion.motionPower.isEmpty {
                    Text("没有足够的连续功率采样，无法计算最佳持续功率。")
                } else if store.isLoading {
                    ProgressView("正在计算最佳持续功率…")
                } else if store.needsWorkoutRefresh {
                    Text("训练已更新，请刷新后查看对应的功率曲线。")
                    Button("刷新训练", action: refreshWorkout)
                } else if let message = store.message {
                    Text(message).foregroundStyle(.secondary)
                    Button("重试") { reload += 1 }.buttonStyle(.bordered)
                } else if let curve = store.curve {
                    results(curve)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(20).fitnessCard()
            if let curve = store.curve {
                Text("单次训练 · W · 包含真实零值。间隔最多 \(curve.maxGapSeconds) 秒时线性插值，更长缺口切断区间，不补零或外推。横轴为持续时长（对数），连线仅辅助阅读；区间时间相对训练开始。")
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
                    LineMark(x: .value("持续秒数", Double(point.durationSeconds)), y: .value("W", best.averagePower))
                        .foregroundStyle(.purple).interpolationMethod(.linear)
                    PointMark(x: .value("持续秒数", Double(point.durationSeconds)), y: .value("W", best.averagePower))
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
            .accessibilityLabel("最佳持续功率曲线，使用下方时长选择或数据列表查看数值")
            Text("\(WorkoutFormat.duration(Double(selected.durationSeconds))) · \(WorkoutFormat.number(effort.averagePower, unit: "W", fractionDigits: 1))")
                .font(.title2.bold()).monospacedDigit().foregroundStyle(.purple)
                .accessibilityIdentifier("powerCurveSelected")
            Text("最佳区间：\(offset(effort.start)) – \(offset(effort.end))").font(.subheadline).foregroundStyle(.secondary)
            Picker("持续时长", selection: Binding(get: { selected.durationSeconds }, set: { selectedDuration = $0 })) {
                ForEach(available, id: \.durationSeconds) { point in
                    Text(WorkoutFormat.duration(Double(point.durationSeconds))).tag(point.durationSeconds)
                }
            }.accessibilityIdentifier("powerCurveDuration")
        } else {
            Text("没有足够的连续功率采样，无法计算最佳持续功率。")
        }
        DisclosureGroup("查看最佳功率数据") {
            ForEach(curve.points, id: \.durationSeconds) { point in
                VStack(alignment: .leading, spacing: 5) {
                    Text(WorkoutFormat.duration(Double(point.durationSeconds))).font(.headline)
                    if let best = point.best {
                        Text(WorkoutFormat.number(best.averagePower, unit: "W", fractionDigits: 1))
                        Text("\(offset(best.start)) – \(offset(best.end))").foregroundStyle(.secondary)
                    } else { Text("连续采样不足").foregroundStyle(.secondary) }
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
