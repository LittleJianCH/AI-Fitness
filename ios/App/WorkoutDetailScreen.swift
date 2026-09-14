import Charts
import ContractClient
import FitnessCore
import MapKit
import SwiftUI

@MainActor
struct WorkoutDetailScreen: View {
    let id: String
    let api: FitnessAPI
    let session: SessionStore
    @State private var showingExport = false
    @State private var store: WorkoutDetailStore
    @State private var retry: Task<Void, Never>?
    @State private var curveReload = 0

    init(id: String, api: FitnessAPI, session: SessionStore) {
        self.id = id
        self.api = api
        self.session = session
        _store = State(initialValue: WorkoutDetailStore(service: api, session: session))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if let workout = store.workout {
                    workoutHeader(workout)
                    SummarySection(title: "记录摘要", summary: workout.recordedCommonSummary, isRunning: workout.sportName == "跑步")
                    RouteSection(positions: workout.motion.motionPosition)
                    ForEach(workout.metrics.filter {
                        !$0.points.isEmpty || ($0.id == "power" && (
                            workout.recordedCommonSummary.summaryPower.averageValue != nil ||
                            workout.recordedCommonSummary.summaryPower.maximumValue != nil
                        ))
                    }) { metric in
                        MetricSection(metric: metric)
                        if metric.id == "power" {
                            PowerCurveSection(workout: workout, api: api, session: session, refreshWorkout: reloadWorkout)
                                .id(curveReload)
                        }
                    }
                    if workout.metrics.contains(where: { $0.points.isEmpty }) {
                        DisclosureGroup("未记录的指标") {
                            ForEach(workout.metrics.filter { $0.points.isEmpty }) { metric in
                                LabeledContent(metric.title, value: "无采样数据").padding(.vertical, 6)
                            }
                        }.font(.subheadline).foregroundStyle(.secondary).padding(20).fitnessCard()
                    }
                    if let calculated = workout.calculatedCommonSummary {
                        DisclosureGroup("后端计算摘要") {
                            SummarySection(title: "计算结果", summary: calculated, isRunning: workout.sportName == "跑步", inCard: false).padding(.top, 12)
                        }.padding(20).fitnessCard()
                    }
                    if workout.workoutUserData.workoutNotes != nil || !workout.workoutUserData.workoutTags.isEmpty || workout.workoutUserData.statisticsInclusion == .excludeFromStatistics {
                        VStack(alignment: .leading, spacing: 14) {
                            FitnessSectionTitle(title: "运动备注")
                            VStack(alignment: .leading, spacing: 14) {
                                if let notes = workout.workoutUserData.workoutNotes { Text(notes).textSelection(.enabled) }
                                if !workout.workoutUserData.workoutTags.isEmpty {
                                    Label(workout.workoutUserData.workoutTags.joined(separator: " · "), systemImage: "tag")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                }
                                if workout.workoutUserData.statisticsInclusion == .excludeFromStatistics {
                                    Label("此记录不计入统计", systemImage: "chart.bar.xaxis").font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(20).fitnessCard()
                        }
                    }
                    if !workout.workoutObservation.observationDataIssues.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            FitnessSectionTitle(title: "数据说明")
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(Array(workout.workoutObservation.observationDataIssues.enumerated()), id: \.offset) { _, issue in
                                    Label(issue.issueDescription, systemImage: "info.circle").font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(20).fitnessCard()
                        }
                    }
                } else if store.isLoading {
                    ProgressView("正在加载详情…").frame(maxWidth: .infinity).padding(40)
                }
                if let message = store.message {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(message, systemImage: "exclamationmark.circle").foregroundStyle(.red)
                        Button("重试", action: reloadWorkout).buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(20).fitnessCard()
                }
            }
            .frame(maxWidth: 760).padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 32)
            .frame(maxWidth: .infinity)
        }
        .background(FitnessStyle.background)
        .navigationTitle("运动详情").navigationBarTitleDisplayMode(.inline)
        .task(id: id) { await store.load(id: id) }
        .refreshable { await refreshDetail() }
        .onDisappear { retry?.cancel() }
        .sheet(isPresented: $showingExport) {
            if let workout = store.workout { HealthExportScreen(workout: workout, api: api, session: session) }
        }
    }

    private func reloadWorkout() {
        retry?.cancel()
        // The detail owns this task: loading removes its power-curve child.
        retry = Task { await refreshDetail() }
    }

    private func refreshDetail() async {
        await store.load(id: id)
        // SwiftUI may coalesce nil -> the same workout into one update. Force
        // the curve to load again even when the detail revision did not change.
        if !Task.isCancelled { curveReload &+= 1 }
    }

    private func workoutHeader(_ workout: Workout) -> some View {
        let running = workout.sportName == "跑步"
        let accent: Color = running ? .orange : .blue
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: running ? "figure.run" : "figure.outdoor.cycle")
                    .font(.title2).foregroundStyle(accent).frame(width: 44, height: 44)
                    .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 14)).accessibilityHidden(true)
                Text(workout.sportName).font(.headline).foregroundStyle(accent)
                Spacer()
                Button { showingExport = true } label: {
                    Image(systemName: "square.and.arrow.up").font(.title3).frame(width: 44, height: 44)
                        .background(FitnessStyle.surface, in: Circle())
                }
                .accessibilityLabel("导出到 Apple 健康").accessibilityIdentifier("openHealthExport")
            }
            Text(workout.displayTitle).font(.largeTitle.bold()).accessibilityIdentifier("workoutTitle")
            VStack(alignment: .leading, spacing: 5) {
                Text(workout.workoutObservation.observationRange.rangeStart.formatted(date: .abbreviated, time: .standard))
                Text("至 " + workout.workoutObservation.observationRange.rangeEnd.formatted(date: .abbreviated, time: .standard))
            }.font(.subheadline).foregroundStyle(.secondary)
            Text("本机时区 · \(TimeZone.current.identifier)").font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

struct SummarySection: View {
    let title: String
    let summary: Components.Schemas.CommonSummary
    let isRunning: Bool
    var inCard = true
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            FitnessSectionTitle(title: title)
            if inCard { content.padding(20).fitnessCard() }
            else { content }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 22) {
            let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 18)) : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
            layout {
                FitnessStat(title: "距离", value: WorkoutFormat.distance(summary.summaryDistance), prominent: true)
                FitnessStat(title: "计时时间", value: WorkoutFormat.duration(summary.summaryTimerTime), prominent: true)
            }
            DisclosureGroup {
                VStack(spacing: 16) {
                    LabeledContent("经过时间", value: WorkoutFormat.duration(summary.summaryElapsedTime))
                    LabeledContent("移动时间", value: WorkoutFormat.duration(summary.summaryMovingTime))
                    LabeledContent("平均心率", value: WorkoutFormat.number(summary.summaryHeartRate.averageValue, unit: "bpm"))
                    LabeledContent("平均功率", value: WorkoutFormat.number(summary.summaryPower.averageValue, unit: "W"))
                    LabeledContent("平均速度", value: WorkoutFormat.number(summary.summarySpeed.averageValue.map { $0 * 3.6 }, unit: "km/h", fractionDigits: 1))
                    if isRunning { LabeledContent("平均配速", value: WorkoutFormat.pace(summary.summarySpeed.averageValue)) }
                    LabeledContent("爬升", value: WorkoutFormat.number(summary.summaryAscent, unit: "m"))
                }.font(.body).foregroundStyle(.primary).monospacedDigit().padding(.top, 16)
            } label: {
                Text("更多摘要指标").frame(minHeight: 44)
            }.font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

struct MetricSection: View {
    let metric: WorkoutMetric
    private var accent: Color {
        switch metric.id {
        case "heartRate": .red
        case "power": .purple
        case "speed": .blue
        case "altitude": .secondary
        default: .teal
        }
    }
    private var symbol: String {
        switch metric.id {
        case "heartRate": "heart.fill"
        case "power": "bolt.fill"
        case "speed": "speedometer"
        case "altitude": "mountain.2.fill"
        default: "metronome.fill"
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            FitnessSectionTitle(title: metric.title, color: accent)
            VStack(alignment: .leading, spacing: 18) {
                if metric.points.isEmpty {
                    Label("无采样数据", systemImage: symbol).font(.subheadline).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    let chartPoints = metric.chartPoints
                    if let last = metric.points.last {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("最后采样", systemImage: symbol).font(.subheadline).foregroundStyle(.secondary)
                            Text(WorkoutFormat.number(last.value, unit: metric.unit, fractionDigits: metric.id == "speed" ? 1 : 0))
                                .font(.system(.title, design: .rounded, weight: .semibold)).monospacedDigit().foregroundStyle(accent)
                        }
                    }
                    Chart(chartPoints) { point in
                        LineMark(x: .value("时间", point.timestamp), y: .value(metric.unit, point.value))
                            .foregroundStyle(accent).lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                            .interpolationMethod(.linear).symbol(.circle)
                            .symbolSize(chartPoints.count == metric.points.count ? 16 : 0)
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .chartYAxis {
                        AxisMarks(position: .trailing) { _ in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 4])).foregroundStyle(Color(uiColor: .separator))
                            AxisValueLabel().foregroundStyle(Color.secondary)
                        }
                    }
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) { _ in AxisValueLabel().foregroundStyle(Color.secondary) } }
                    .frame(height: 180).accessibilityLabel(metric.title)
                    Text("\(metric.points.count) 个采样点 · \(metric.unit)").font(.subheadline).foregroundStyle(.secondary)
                    if chartPoints.count < metric.points.count {
                        Text("概览保留分段峰谷，原始采样完整保留。")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(20).fitnessCard()
            if !metric.points.isEmpty {
                Text("连线仅辅助阅读，空档不代表有记录。")
                    .font(.subheadline).foregroundStyle(.secondary).padding(.horizontal, 4)
            }
        }
        .accessibilityIdentifier("metric-\(metric.id)")
    }
}

struct RouteSection: View {
    let positions: [Components.Schemas.Timed_Position]
    var inCard = true
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            FitnessSectionTitle(title: "路线", color: .blue)
            if positions.isEmpty {
                Label("无路线数据", systemImage: "map")
                    .font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(inCard ? 20 : 0)
                    .background(inCard ? FitnessStyle.surface : Color.clear, in: RoundedRectangle(cornerRadius: FitnessStyle.radius, style: .continuous))
            } else {
                VStack(spacing: 0) {
                    Map {
                        MapPolyline(coordinates: positions.map { CLLocationCoordinate2D(latitude: $0.value.latitude, longitude: $0.value.longitude) })
                            .stroke(.blue, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    }
                    .frame(height: 270).accessibilityLabel("运动记录路线")
                    HStack {
                        Label("记录路线", systemImage: "map")
                        Spacer()
                        Text("\(positions.count) 个位置点").monospacedDigit()
                    }.font(.subheadline).foregroundStyle(.secondary).padding(16)
                }
                .background(inCard ? FitnessStyle.surface : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: inCard ? FitnessStyle.radius : 16, style: .continuous))
            }
        }
        .accessibilityIdentifier("workoutRoute")
    }
}
