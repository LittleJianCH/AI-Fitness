import Charts
import ContractClient
import FitnessCore
import SwiftUI

@MainActor
struct WorkoutAnalysisSection: View {
    let workout: Workout
    let api: FitnessAPI
    let session: SessionStore
    let refreshWorkout: () -> Void
    @State private var store: WorkoutAnalysisStore
    @State private var retry: Task<Void, Never>?

    init(workout: Workout, api: FitnessAPI, session: SessionStore, refreshWorkout: @escaping () -> Void) {
        self.workout = workout
        self.api = api
        self.session = session
        self.refreshWorkout = refreshWorkout
        _store = State(initialValue: WorkoutAnalysisStore(service: api, session: session))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            if let analysis = store.analysis {
                ForEach(workout.metrics.filter { !$0.points.isEmpty }) { metric in
                    if let statistics = analysis.analysisMetrics.first(where: { $0.metricKind.rawValue == metric.id + "Metric" }) {
                        MetricAnalysisCard(workout: workout, metric: metric, statistics: statistics, analysis: analysis)
                    }
                    if metric.id == "power" {
                        PowerSummaryCard(power: analysis.analysisPower)
                        PowerCurveSection(workout: workout, api: api, session: session, refreshWorkout: refreshWorkout)
                    }
                }
                if workout.motion.motionPower.isEmpty && (workout.recordedCommonSummary.summaryPower.averageValue != nil || workout.recordedCommonSummary.summaryPower.maximumValue != nil) {
                    PowerCurveSection(workout: workout, api: api, session: session, refreshWorkout: refreshWorkout)
                }
                HeartLoadCard(heart: analysis.analysisHeart)
                NavigationLink {
                    TrainingHistoryScreen(api: api, session: session, ending: min(Date(), workout.workoutObservation.observationRange.rangeStart))
                } label: {
                    Label("体能与疲劳趋势", systemImage: "chart.xyaxis.line")
                        .frame(maxWidth: .infinity, alignment: .leading).padding(20).fitnessCard()
                }
                if let running = analysis.analysisRunning { RunningDynamicsCard(running: running) }
                SplitAnalysisCard(sets: analysis.analysisSplits, halves: analysis.analysisHalves, isRunning: workout.sportName == "跑步")
                DisclosureGroup("分析方法与个人参数") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("统计与分布按时间加权，最多连接相邻 120 秒内的采样。零值保留，空档不补零。")
                        Text("功率计算仅连接相邻 5 秒内的采样。标准化功率使用完整的 30 秒滚动窗口；短于 10 分钟的结果需谨慎解读。")
                        Text("分段与传感器均值使用经过时间，包含停车。心率负荷优先使用记录中的计时事件排除暂停。")
                        if let profile = analysis.analysisBodyProfile {
                            LabeledContent("个人参数生效时间", value: profile.bodyEffectiveFrom.formatted(date: .abbreviated, time: .shortened))
                        } else { Text("运动开始时没有生效的个人参数；可在「设置 → 个人身体参数」中添加。") }
                        LabeledContent("算法", value: analysis.analysisMethod)
                        LabeledContent("参数版本", value: analysis.analysisSettingsRevision)
                    }.font(.footnote).foregroundStyle(.secondary).padding(.top, 12)
                }.padding(20).fitnessCard()
            } else if store.isLoading { ProgressView("正在分析运动…").frame(maxWidth: .infinity) }
            if store.needsWorkoutRefresh {
                Label("运动记录已更新，请重新加载详情。", systemImage: "arrow.clockwise")
                Button("重新加载详情", action: refreshWorkout)
            }
            if let message = store.message {
                Text(message).foregroundStyle(.red)
                Button("重试分析") { retry = Task { await load() } }
            }
        }
        .task(id: workout.workoutRevision) { await load() }
        .onDisappear { retry?.cancel() }
    }

    private func load() async { await store.load(id: workout.workoutId, revision: workout.workoutRevision) }
}

private struct MetricAnalysisCard: View {
    let workout: Workout
    let metric: WorkoutMetric
    let statistics: MetricAnalysis
    let analysis: WorkoutAnalysis

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            FitnessSectionTitle(title: metric.title, color: metric.accent)
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    if metric.id == "speed", workout.sportName == "跑步" {
                        FitnessStat(title: "平均配速", value: WorkoutFormat.pace(statistics.metricStatistics.averageValue), prominent: true)
                        FitnessStat(title: "最快采样配速", value: WorkoutFormat.pace(statistics.metricStatistics.maximumValue))
                    } else {
                        FitnessStat(title: "平均", value: metric.displayValue(statistics.metricStatistics.averageValue), prominent: true)
                        FitnessStat(title: "最大", value: metric.displayValue(statistics.metricStatistics.maximumValue))
                    }
                }
                MetricTimeline(workout: workout, metric: metric, axis: .time)
                    .frame(height: 165).accessibilityIdentifier("metric-\(metric.id)")
                HStack {
                    Text("有效覆盖 " + WorkoutFormat.duration(statistics.metricCoveredSeconds))
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    NavigationLink("详细分析") {
                        MetricAnalysisScreen(workout: workout, metric: metric, statistics: statistics, analysis: analysis)
                    }.font(.subheadline.weight(.semibold))
                        .accessibilityIdentifier("metricAnalysis-\(metric.id)")
                }
            }.padding(20).fitnessCard()
        }
    }
}

struct PowerSummaryCard: View {
    let power: Components.Schemas.PowerAnalysis
    var body: some View {
        AnalysisCard(title: "功率分析", color: .purple) {
            analysisRow("标准化功率", power.powerNormalized, "W")
            analysisRow("变异指数", power.powerVariabilityIndex, "", digits: 2)
            analysisRow("强度因子", power.powerIntensityFactor, "", digits: 2)
            analysisRow("功率训练压力", power.powerStressScore, "", digits: 1)
            analysisRow("平均功率 / 体重", power.powerWattsPerKilogram, "W/kg", digits: 2)
            analysisRow("观测机械功", power.powerWorkJoules.map { $0 / 1000 }, "kJ", digits: 1)
            analysisRow("效率因子", power.powerEfficiency, "W/bpm", digits: 2)
            analysisRow("前后半程功率 / 心率解耦", power.powerDecouplingPercent, "%", digits: 1)
            Divider()
            analysisRow("使用的阈值功率", power.powerThresholdWatts, "W")
            analysisRow("使用的体重", power.powerAthleteKilograms, "kg", digits: 1)
            Text("源记录中的体重和阈值优先。训练压力、效率和解耦需要完整覆盖；没有依据时显示无数据。")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}

private struct HeartLoadCard: View {
    let heart: Components.Schemas.HeartAnalysis
    private var status: String {
        switch heart.heartLoadStatus {
        case .heartLoadAvailable: "采样覆盖满足要求"
        case .heartProfileMissing: "请在设置中补充该运动开始时生效的心率参数"
        case .heartCoverageInsufficient: "心率覆盖不足 95%，以下仅为已观测部分的负荷"
        case .heartNoActiveTime: "没有有效计时时间"
        case .heartExcluded: "此运动不计入统计"
        case .heartCalculationUnavailable: "当前数据无法计算心率负荷"
        }
    }
    var body: some View {
        AnalysisCard(title: "心率与训练负荷", color: .red) {
            Text(status).font(.subheadline).foregroundStyle(.secondary)
            analysisRow("HRSS", heart.heartHrss, "", digits: 1)
            analysisRow("TRIMPexp", heart.heartTrimp, "", digits: 1)
            analysisRow("心率覆盖率", heart.heartCoverageFraction.map { $0 * 100 }, "%", digits: 1)
            LabeledContent("计时依据", value: heart.heartUsesRecordedTimer ? "记录中的计时事件" : "经过时间")
            if !heart.heartZones.isEmpty {
                ZoneChart(zones: heart.heartZones, unit: "bpm", heart: true)
                Text("区间按心率储备划分：50%、60%、70%、80%、90%。Z0 低于 50%；Z6 为达到或超过配置的最大心率。超出最大心率的读数不计入负荷。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

private struct RunningDynamicsCard: View {
    let running: Components.Schemas.RunningAnalysis
    var body: some View {
        AnalysisCard(title: "跑姿", color: .orange) {
            analysisRow("步数（完整步频积分）", running.runningSteps, "步")
            analysisRow("腾空时间", running.runningFlightSeconds.map { $0 * 1000 }, "ms")
            analysisRow("垂直比", running.runningVerticalRatioPercent, "%", digits: 1)
            analysisRow("腾空比", running.runningFlightRatioPercent, "%", digits: 1)
            analysisRow("跑步效率", running.runningEffectiveness, "", digits: 2)
            Text("腾空时间由步频和触地时间计算，垂直比由垂直振幅和每步步长计算；需要同时存在的有效采样。")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}

struct SplitAnalysisCard: View {
    let sets: [Components.Schemas.SplitSet]
    let halves: Components.Schemas.SplitComparison?
    let isRunning: Bool
    @State private var length = 1000.0
    private var splits: [Components.Schemas.DistanceSplit] { sets.first { $0.splitLengthMetres == length }?.distanceSplits ?? [] }

    var body: some View {
        AnalysisCard(title: "距离分段", color: .blue) {
            Picker("分段长度", selection: $length) {
                Text("1 km").tag(1000.0)
                Text("5 km").tag(5000.0)
            }.pickerStyle(.segmented)
            if splits.isEmpty {
                Text("需要连续、递增的距离采样才能计算分段。缺失或距离重置时不推算。")
                    .foregroundStyle(.secondary)
            } else {
                Chart(splits.prefix(100), id: \.splitIndex) { split in
                    BarMark(x: .value("分段", String(split.splitIndex)), y: .value("km/h", split.splitAverageSpeed * 3.6))
                        .foregroundStyle(.blue.gradient)
                }.frame(height: 140)
                NavigationLink("查看全部 \(splits.count) 个分段") {
                    List(splits, id: \.splitIndex) { split in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("第 \(split.splitIndex) 段").font(.headline)
                                Spacer()
                                Text(WorkoutFormat.distance(split.splitDistanceMetres))
                            }
                            LabeledContent("用时", value: WorkoutFormat.duration(split.splitEndSeconds - split.splitStartSeconds))
                            LabeledContent(isRunning ? "配速" : "速度", value: isRunning ? WorkoutFormat.pace(split.splitAverageSpeed) : WorkoutFormat.number(split.splitAverageSpeed * 3.6, unit: "km/h", fractionDigits: 1))
                            analysisRow("心率", split.splitHeartRate, "bpm")
                            analysisRow("功率", split.splitPower, "W")
                            analysisRow(isRunning ? "步频" : "踏频", split.splitCadence, isRunning ? "步/分" : "rpm")
                            analysisRow("净海拔变化", split.splitElevationChange, "m")
                        }.padding(.vertical, 8)
                    }.navigationTitle("\(Int(length / 1000)) km 分段")
                }.accessibilityIdentifier("distanceSplits")
            }
            if let halves {
                Divider()
                LabeledContent("前半程", value: speed(halves.firstHalfSpeed))
                LabeledContent("后半程", value: speed(halves.secondHalfSpeed))
                analysisRow("后半程速度变化", halves.secondHalfChangePercent, "%", digits: 1)
            }
            Text("按经过时间计算，包含停止时间。末段保留实际距离。")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
    private func speed(_ value: Double) -> String { isRunning ? WorkoutFormat.pace(value) : WorkoutFormat.number(value * 3.6, unit: "km/h", fractionDigits: 1) }
}

struct ZoneChart: View {
    let zones: [Components.Schemas.ZoneDuration]
    let unit: String
    var heart = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Chart(zones, id: \.zoneIndex) { zone in
                BarMark(x: .value("分钟", zone.zoneSeconds / 60), y: .value("区间", "Z\(zone.zoneIndex)"))
                    .foregroundStyle(by: .value("区间", "Z\(zone.zoneIndex)"))
            }.chartLegend(.hidden).frame(height: 190)
            ForEach(zones, id: \.zoneIndex) { zone in
                HStack {
                    Text("Z\(zone.zoneIndex)").fontWeight(.semibold)
                    Text(WorkoutFormat.number(zone.zoneLower, unit: "") + "–" + (zone.zoneUpper.map { WorkoutFormat.number($0, unit: unit) } ?? "以上"))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(WorkoutFormat.duration(zone.zoneSeconds)).monospacedDigit()
                }.font(.caption)
            }
        }
    }
}

struct AnalysisCard<Content: View>: View {
    let title: String
    var color: Color = .primary
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            FitnessSectionTitle(title: title, color: color)
            VStack(alignment: .leading, spacing: 14, content: content)
                .frame(maxWidth: .infinity, alignment: .leading).padding(20).fitnessCard()
        }
    }
}

func analysisRow(_ title: String, _ value: Double?, _ unit: String, digits: Int = 0) -> some View {
    LabeledContent(title, value: WorkoutFormat.number(value, unit: unit, fractionDigits: digits)).monospacedDigit()
}

extension WorkoutMetric {
    var accent: Color {
        switch id {
        case "heartRate": .red
        case "power": .purple
        case "speed": .blue
        case "altitude": .secondary
        case "cadence": .teal
        default: .orange
        }
    }
}
