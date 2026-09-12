import Charts
import ContractClient
import FitnessCore
import MapKit
import SwiftUI

@MainActor
struct WorkoutDetailScreen: View {
    let id: String
    @State private var store: WorkoutDetailStore
    @State private var retry: Task<Void, Never>?

    init(id: String, api: FitnessAPI, session: SessionStore) {
        self.id = id
        _store = State(initialValue: WorkoutDetailStore(service: api, session: session))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let workout = store.workout {
                    Text(workout.displayTitle).font(.largeTitle.bold()).accessibilityIdentifier("workoutTitle")
                    VStack(alignment: .leading, spacing: 8) {
                        Text(workout.sportName).font(.headline)
                        Text(workout.workoutObservation.observationRange.rangeStart.formatted(date: .abbreviated, time: .standard))
                        Text("至 " + workout.workoutObservation.observationRange.rangeEnd.formatted(date: .abbreviated, time: .standard))
                        Text("时间按本机时区显示：\(TimeZone.current.identifier)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    SummarySection(title: "记录摘要", summary: workout.recordedCommonSummary, isRunning: workout.sportName == "跑步")
                    if let calculated = workout.calculatedCommonSummary {
                        SummarySection(title: "后端计算摘要", summary: calculated, isRunning: workout.sportName == "跑步")
                    }
                    if let notes = workout.workoutUserData.workoutNotes {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("备注").font(.headline)
                            Text(notes).textSelection(.enabled)
                        }
                    }
                    if !workout.workoutUserData.workoutTags.isEmpty {
                        Text(workout.workoutUserData.workoutTags.joined(separator: " · "))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    if workout.workoutUserData.statisticsInclusion == .excludeFromStatistics {
                        Label("此记录不计入统计", systemImage: "chart.bar.xaxis")
                    }
                    RouteSection(positions: workout.motion.motionPosition)
                    ForEach(workout.metrics) { metric in MetricSection(metric: metric) }
                    if !workout.workoutObservation.observationDataIssues.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("数据说明").font(.headline)
                            ForEach(Array(workout.workoutObservation.observationDataIssues.enumerated()), id: \.offset) { _, issue in
                                Text(issue.issueDescription).font(.subheadline)
                            }
                        }
                    }
                } else if store.isLoading {
                    ProgressView("正在加载详情…").frame(maxWidth: .infinity)
                }
                if let message = store.message {
                    Text(message).foregroundStyle(.red)
                    Button("重试") { retry = Task { await store.load(id: id) } }
                }
            }
            .padding()
        }
        .navigationTitle("运动详情")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: id) { await store.load(id: id) }
        .refreshable { await store.load(id: id) }
        .onDisappear { retry?.cancel() }
    }
}

struct SummarySection: View {
    let title: String
    let summary: Components.Schemas.CommonSummary
    let isRunning: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title3.bold())
            LabeledContent("距离", value: WorkoutFormat.distance(summary.summaryDistance))
            LabeledContent("经过时间", value: WorkoutFormat.duration(summary.summaryElapsedTime))
            LabeledContent("计时时间", value: WorkoutFormat.duration(summary.summaryTimerTime))
            LabeledContent("移动时间", value: WorkoutFormat.duration(summary.summaryMovingTime))
            LabeledContent("平均心率", value: WorkoutFormat.number(summary.summaryHeartRate.averageValue, unit: "bpm"))
            LabeledContent("平均功率", value: WorkoutFormat.number(summary.summaryPower.averageValue, unit: "W"))
            LabeledContent("平均速度", value: WorkoutFormat.number(summary.summarySpeed.averageValue.map { $0 * 3.6 }, unit: "km/h", fractionDigits: 1))
            if isRunning { LabeledContent("平均配速", value: WorkoutFormat.pace(summary.summarySpeed.averageValue)) }
            LabeledContent("爬升", value: WorkoutFormat.number(summary.summaryAscent, unit: "m"))
        }
        .padding().background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct MetricSection: View {
    let metric: WorkoutMetric
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(metric.title) · \(metric.unit)").font(.title3.bold())
            if metric.points.isEmpty {
                Text("无采样数据").foregroundStyle(.secondary)
            } else {
                Chart(metric.points) { point in
                    LineMark(x: .value("时间", point.timestamp), y: .value(metric.unit, point.value))
                    PointMark(x: .value("时间", point.timestamp), y: .value(metric.unit, point.value))
                        .symbolSize(8)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 180)
                .accessibilityLabel(metric.title)
                Text("\(metric.points.count) 个采样点，连线仅辅助阅读，空档不代表有记录")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("metric-\(metric.id)")
    }
}

struct RouteSection: View {
    let positions: [Components.Schemas.Timed_Position]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("路线").font(.title3.bold())
            if positions.isEmpty {
                Text("无路线数据").foregroundStyle(.secondary)
            } else {
                Map {
                    MapPolyline(coordinates: positions.map { CLLocationCoordinate2D(latitude: $0.value.latitude, longitude: $0.value.longitude) })
                        .stroke(.blue, lineWidth: 3)
                }
                .frame(height: 260)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .accessibilityLabel("运动记录路线")
            }
        }
        .accessibilityIdentifier("workoutRoute")
    }
}
