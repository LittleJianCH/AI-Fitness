import Charts
import ContractClient
import FitnessCore
import SwiftUI

enum MetricAxis: String, CaseIterable { case time = "时间", distance = "距离" }

struct MetricAnalysisScreen: View {
    let workout: Workout
    let metric: WorkoutMetric
    let statistics: MetricAnalysis?
    let analysis: WorkoutAnalysis?
    @State private var axis: MetricAxis = .time
    @State private var comparison = ""
    @State private var selection: Double?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                AnalysisCard(title: metric.title, color: metric.accent) {
                    Picker("横轴", selection: $axis) {
                        ForEach(MetricAxis.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented).accessibilityIdentifier("metricAxis")
                    MetricTimeline(workout: workout, metric: metric, axis: axis, selection: $selection)
                        .frame(height: 240)
                    LabeledContent("对照指标") {
                        Picker("对照指标", selection: $comparison) {
                            Text("无").tag("")
                            ForEach(workout.metrics.filter { $0.id != metric.id && !$0.points.isEmpty }) { Text($0.title).tag($0.id) }
                        }.labelsHidden().accessibilityIdentifier("comparisonMetric")
                    }
                    if let other = workout.metrics.first(where: { $0.id == comparison }) {
                        Text(other.title + " · " + other.unit).font(.subheadline).foregroundStyle(other.accent)
                        MetricTimeline(workout: workout, metric: other, axis: axis, selection: $selection)
                            .frame(height: 150)
                        Text("两张图共享横轴位置，各自保留原始单位。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let statistics {
                        LabeledContent("平均", value: metric.displayValue(statistics.metricStatistics.averageValue))
                        LabeledContent("排除零平台的平均", value: metric.displayValue(statistics.metricAverageExcludingZeros))
                        LabeledContent("最小", value: metric.displayValue(statistics.metricStatistics.minimumValue))
                        LabeledContent("最大", value: metric.displayValue(statistics.metricStatistics.maximumValue))
                        LabeledContent("有效覆盖", value: WorkoutFormat.duration(statistics.metricCoveredSeconds))
                        LabeledContent("原始采样", value: "\(statistics.metricSampleCount) 个")
                        if metric.id == "speed", workout.sportName == "跑步" {
                            LabeledContent("平均配速", value: WorkoutFormat.pace(statistics.metricStatistics.averageValue))
                            LabeledContent("最快采样配速", value: WorkoutFormat.pace(statistics.metricStatistics.maximumValue))
                        }
                    } else {
                        Text("派生统计暂不可用，可返回运动详情重试分析。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if let statistics {
                    AnalysisCard(title: "分布", color: metric.accent) {
                        Chart(Array(statistics.metricDistribution.enumerated()), id: \.offset) { _, bin in
                            RectangleMark(xStart: .value(metric.unit, bin.binLower * metric.canonicalScale),
                                    xEnd: .value(metric.unit, bin.binUpper * metric.canonicalScale),
                                    yStart: .value("分钟", 0),
                                    yEnd: .value("分钟", bin.binSeconds / 60))
                                .foregroundStyle(metric.accent.gradient)
                        }.frame(height: 220)
                        Text("横轴 \(metric.unit) · 纵轴分钟。基于有效时间覆盖，不按采样点数量计数。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if let analysis {
                    if metric.id == "power", !analysis.analysisPowerZones.isEmpty {
                        AnalysisCard(title: "功率区间", color: .purple) {
                            ZoneChart(zones: analysis.analysisPowerZones, unit: "W")
                            Text("阈值功率的 55%、75%、90%、105%、120%、150% 为区间边界。只计入有效功率覆盖。")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    ForEach(Array(analysis.analysisRelationships.filter { $0.relationshipX.rawValue == metric.id + "Metric" }.enumerated()), id: \.offset) { _, relationship in
                        if let other = workout.metrics.first(where: { $0.id + "Metric" == relationship.relationshipY.rawValue }) {
                            RelationshipCard(metric: metric, other: other, relationship: relationship)
                        }
                    }
                }
            }.padding(20).frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .background(FitnessStyle.background).navigationTitle(metric.title + "分析").navigationBarTitleDisplayMode(.inline)
        .onChange(of: axis) { _, _ in selection = nil }
    }
}

private struct RelationshipCard: View {
    let metric: WorkoutMetric
    let other: WorkoutMetric
    let relationship: Components.Schemas.MetricRelationship
    var body: some View {
        AnalysisCard(title: metric.title + "与" + other.title, color: metric.accent) {
            Chart(Array(relationship.relationshipPoints.enumerated()), id: \.offset) { _, point in
                PointMark(x: .value(metric.unit, point.relationshipXValue * metric.canonicalScale),
                          y: .value(other.unit, point.relationshipYValue * other.canonicalScale))
                    .foregroundStyle(metric.accent.opacity(0.5)).symbolSize(12)
            }.frame(height: 220)
                .chartXAxisLabel(metric.title + " · " + metric.unit)
                .chartYAxisLabel(other.title + " · " + other.unit)
            analysisRow("相关系数", relationship.relationshipCorrelation, "", digits: 2)
            Text("\(relationship.relationshipSampleCount) 对有效采样，图上最多展示 600 对。相关不代表因果。")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}

/// Downsampling affects rendering only. Segment identities come from the full
/// stream so decimation cannot fabricate a sensor gap or bridge an existing one.
struct MetricTimeline: View {
    let workout: Workout
    let metric: WorkoutMetric
    let axis: MetricAxis
    var selection: Binding<Double?>?
    @State private var localSelection: Double?

    private struct Point: Identifiable {
        let id: Date
        let x: Double
        let y: Double
        let segment: Int
    }

    private var points: [Point] {
        let shown = Set(metric.chartPoints.map(\.timestamp))
        var segment = 0
        var previous: Date?
        var previousX: Double?
        return metric.points.compactMap { point in
            if let previous, point.timestamp.timeIntervalSince(previous) > 120 { segment += 1 }
            previous = point.timestamp
            guard let x = coordinate(point.timestamp) else { segment += 1; return nil }
            if let previousX, x < previousX { segment += 1 }
            previousX = x
            guard shown.contains(point.timestamp) else { return nil }
            return Point(id: point.timestamp, x: x, y: point.value, segment: segment)
        }
    }

    private var xDomain: ClosedRange<Double> {
        let range = workout.workoutObservation.observationRange
        if axis == .time { return 0...max(1, range.rangeEnd.timeIntervalSince(range.rangeStart)) }
        return 0...max(0.001, (workout.motion.motionDistance.last?.value ?? 0) / 1000)
    }

    var body: some View {
        let rendered = points
        let selected = selection?.wrappedValue ?? localSelection
        let nearest = selected.flatMap { metric.nearestPoint(to: $0, coordinate: coordinate) }
        VStack(alignment: .leading, spacing: 6) {
            if rendered.isEmpty { Text("没有可用于此横轴的采样").font(.caption).foregroundStyle(.secondary) }
            else {
                let chart = Chart {
                    ForEach(rendered) { point in
                        LineMark(x: .value(axis.rawValue, point.x), y: .value(metric.unit, point.y), series: .value("连续段", point.segment))
                            .foregroundStyle(metric.accent).lineStyle(StrokeStyle(lineWidth: 2))
                        if rendered.count < 3 { PointMark(x: .value(axis.rawValue, point.x), y: .value(metric.unit, point.y)).foregroundStyle(metric.accent) }
                    }
                    if let nearest, let x = coordinate(nearest.timestamp) {
                        RuleMark(x: .value(axis.rawValue, x)).foregroundStyle(.secondary.opacity(0.6))
                        PointMark(x: .value(axis.rawValue, x), y: .value(metric.unit, nearest.value)).foregroundStyle(metric.accent)
                    }
                }
                .chartXScale(domain: xDomain)
                .chartXSelection(value: selection ?? $localSelection)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let x = value.as(Double.self) { Text(axis == .time ? "\(Int(x / 60))′" : x.formatted(.number.precision(.fractionLength(1)))) }
                        }
                    }
                }
                .chartXAxisLabel(axis == .time ? "经过时间（分钟）" : "距离（km）")
                .accessibilityLabel(metric.title + "随" + axis.rawValue + "变化")
                if let value = rendered.first?.y, rendered.allSatisfy({ $0.y == value }) {
                    // Automatic singleton domains can reverse negative axes.
                    // This range is display padding, not additional samples.
                    let padding = max(1, abs(value) * 0.05)
                    let lower = max(-Double.greatestFiniteMagnitude, value - padding)
                    let upper = min(Double.greatestFiniteMagnitude, value + padding)
                    chart.chartYScale(domain: lower...upper)
                } else {
                    chart.chartYScale(domain: .automatic(includesZero: false))
                }
                if let nearest {
                    Text(WorkoutFormat.number(nearest.value, unit: metric.unit, fractionDigits: metric.fractionDigits)
                        + " · " + nearest.timestamp.formatted(date: .omitted, time: .standard))
                        .font(.caption).monospacedDigit().foregroundStyle(metric.accent)
                }
            }
        }
    }

    private func coordinate(_ time: Date) -> Double? {
        if axis == .time { return time.timeIntervalSince(workout.workoutObservation.observationRange.rangeStart) }
        let distances = workout.motion.motionDistance
        var low = 0
        var high = distances.count
        while low < high {
            let middle = (low + high) / 2
            if distances[middle].timestamp < time { low = middle + 1 } else { high = middle }
        }
        if low < distances.count, distances[low].timestamp == time { return distances[low].value / 1000 }
        guard low > 0, low < distances.count else { return nil }
        let before = distances[low-1]
        let after = distances[low]
        let gap = after.timestamp.timeIntervalSince(before.timestamp)
        guard gap > 0, gap <= 120, after.value >= before.value else { return nil }
        let fraction = time.timeIntervalSince(before.timestamp) / gap
        return (before.value * (1-fraction) + after.value * fraction) / 1000
    }
}
