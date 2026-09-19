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
                    WorkoutAnalysisSection(workout: workout, api: api, session: session, refreshWorkout: reloadWorkout)
                        .id(curveReload)
                    RecordedDetailsSection(workout: workout)
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


struct RouteSection: View {
    let positions: [Components.Schemas.Timed_Position]
    var inCard = true
    @State private var fullScreen = false
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
                    WorkoutRouteMap(positions: positions)
                    .frame(height: 270).accessibilityLabel("运动记录路线")
                    HStack {
                        Button { fullScreen = true } label: { Label("展开地图", systemImage: "arrow.up.left.and.arrow.down.right") }
                            .accessibilityIdentifier("expandRoute")
                        Spacer()
                        Text("\(positions.count) 个位置点").monospacedDigit()
                    }.font(.subheadline).foregroundStyle(.secondary).padding(16)
                }
                .background(inCard ? FitnessStyle.surface : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: inCard ? FitnessStyle.radius : 16, style: .continuous))
            }
        }
        .accessibilityIdentifier("workoutRoute")
        .sheet(isPresented: $fullScreen) {
            NavigationStack {
                WorkoutRouteMap(positions: positions, controls: true)
                    .navigationTitle("运动路线").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { fullScreen = false } } }
            }
        }
    }
}

private struct WorkoutRouteMap: View {
    let positions: [Components.Schemas.Timed_Position]
    var controls = false
    @State private var satellite = false

    private var segments: [[CLLocationCoordinate2D]] {
        var result: [[CLLocationCoordinate2D]] = []
        var current: [CLLocationCoordinate2D] = []
        var previous: Date?
        for point in positions {
            if let previous, point.timestamp.timeIntervalSince(previous) > 120 {
                if !current.isEmpty { result.append(current) }
                current = []
            }
            current.append(.init(latitude: point.value.latitude, longitude: point.value.longitude))
            previous = point.timestamp
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    var body: some View {
        Map {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, coordinates in
                MapPolyline(coordinates: coordinates).stroke(.blue, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }
            if let first = positions.first {
                Marker("起点", coordinate: .init(latitude: first.value.latitude, longitude: first.value.longitude)).tint(.green)
            }
            if let last = positions.last {
                Marker("终点", coordinate: .init(latitude: last.value.latitude, longitude: last.value.longitude)).tint(.red)
            }
        }
        .mapStyle(satellite ? .hybrid : .standard)
        .overlay(alignment: .topTrailing) {
            if controls {
                Button(satellite ? "标准地图" : "卫星地图") { satellite.toggle() }
                    .buttonStyle(.borderedProminent).padding()
            }
        }
    }
}

private struct RecordedDetailsSection: View {
    let workout: Workout
    private struct Lap: Identifiable {
        let id: Int
        let range: Components.Schemas.TimeRange
        let summary: Components.Schemas.CommonSummary
    }
    private var laps: [Lap] {
        switch workout.workoutObservation.observationSport {
        case .case1(let sport): sport.data.cyclingLaps.enumerated().map { .init(id: $0.offset, range: $0.element.lapRange, summary: $0.element.lapSummary.recordedSummary.cyclingCommonSummary) }
        case .case2(let sport): sport.data.runningLaps.enumerated().map { .init(id: $0.offset, range: $0.element.lapRange, summary: $0.element.lapSummary.recordedSummary.runningCommonSummary) }
        }
    }

    var body: some View {
        let summary = workout.recordedCommonSummary
        AnalysisCard(title: "海拔、能量与环境", color: .teal) {
            analysisRow("累计爬升", summary.summaryAscent, "m")
            analysisRow("累计下降", summary.summaryDescent, "m")
            analysisRow("最低海拔", summary.summaryAltitude.minimumValue, "m")
            analysisRow("最高海拔", summary.summaryAltitude.maximumValue, "m")
            analysisRow("代谢能量", summary.summaryMetabolicEnergy.map { $0 / 4184 }, "kcal")
            analysisRow("机械功", summary.summaryMechanicalWork.map { $0 / 1000 }, "kJ")
            analysisRow("平均气温", summary.summaryTemperature.averageValue, "°C", digits: 1)
            Text("以上保留源记录的摘要，代谢能量与机械功分别展示。没有记录的指标不会用估值补齐。")
                .font(.footnote).foregroundStyle(.secondary)
        }
        if !laps.isEmpty {
            AnalysisCard(title: "设备记录的分段") {
                NavigationLink("查看 \(laps.count) 个记录分段") {
                    List(laps) { lap in
                        VStack(alignment: .leading, spacing: 12) {
                            Text("分段 \(lap.id + 1)").font(.headline)
                            Text(lap.range.rangeStart.formatted(date: .omitted, time: .standard) + "–" + lap.range.rangeEnd.formatted(date: .omitted, time: .standard)).font(.caption).foregroundStyle(.secondary)
                            LabeledContent("距离", value: WorkoutFormat.distance(lap.summary.summaryDistance))
                            LabeledContent("计时时间", value: WorkoutFormat.duration(lap.summary.summaryTimerTime))
                            analysisRow("平均功率", lap.summary.summaryPower.averageValue, "W")
                            analysisRow("平均心率", lap.summary.summaryHeartRate.averageValue, "bpm")
                            LabeledContent("平均配速", value: WorkoutFormat.pace(lap.summary.summarySpeed.averageValue))
                        }.padding(.vertical, 8)
                    }.navigationTitle("设备分段")
                }
            }
        }
        if case .case1(let sport) = workout.workoutObservation.observationSport {
            let context = sport.data.cyclingContext
            if context.bicycleName != nil || context.bicycleMass != nil || context.cyclingDiscipline != nil {
                AnalysisCard(title: "运动中的器材") {
                    if let name = context.bicycleName { LabeledContent("自行车", value: name) }
                    if let discipline = context.cyclingDiscipline { LabeledContent("骑行类型", value: discipline) }
                    analysisRow("自行车重量", context.bicycleMass, "kg", digits: 1)
                }
            }
        }
    }
}
