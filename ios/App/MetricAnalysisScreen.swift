import Charts
import ContractClient
import FitnessCore
import SwiftUI

enum MetricAxis: CaseIterable {
    case time, distance
    var resource: LocalizedStringResource { self == .time ? "Time" : "Distance" }
    var localizedTitle: String { String(localized: resource) }
}

struct MetricAnalysisScreen: View {
    let workout: Workout
    let metric: WorkoutMetric
    let statistics: MetricAnalysis?
    let analysis: WorkoutAnalysis?
    @State private var axis: MetricAxis = .time
    @State private var comparison = ""
    @State private var comparisonMetrics: [WorkoutMetric] = []
    @State private var selection: Double?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                AnalysisCard(title: metric.titleResource, color: metric.accent) {
                    Picker("Horizontal axis", selection: $axis) {
                        ForEach(MetricAxis.allCases, id: \.self) { LocalizedText($0.resource).tag($0) }
                    }.pickerStyle(.segmented).accessibilityIdentifier("metricAxis")
                    MetricTimeline(workout: workout, metric: metric, axis: axis, selection: $selection)
                        .frame(height: 240)
                    LabeledContent(String(localized: "Compare metric")) {
                        Picker("Compare metric", selection: $comparison) {
                            Text("None").tag("")
                            ForEach(comparisonMetrics.filter { $0.id != metric.id && !$0.points.isEmpty }) { Text($0.localizedTitle).tag($0.id) }
                        }.labelsHidden().accessibilityIdentifier("comparisonMetric")
                    }
                    if let other = comparisonMetrics.first(where: { $0.id == comparison }) {
                        Text(other.localizedTitle + " · " + other.unit).font(.subheadline).foregroundStyle(other.accent)
                        MetricTimeline(workout: workout, metric: other, axis: axis, selection: $selection)
                            .frame(height: 150)
                        Text("Both charts share horizontal positions and retain their original units.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let statistics {
                        LabeledContent(String(localized: "Average"), value: metric.localizedValue(statistics.metricStatistics.averageValue))
                        LabeledContent(String(localized: "Average excluding zero plateaus"), value: metric.localizedValue(statistics.metricAverageExcludingZeros))
                        LabeledContent(String(localized: "Minimum"), value: metric.localizedValue(statistics.metricStatistics.minimumValue))
                        LabeledContent(String(localized: "Maximum"), value: metric.localizedValue(statistics.metricStatistics.maximumValue))
                        LabeledContent(String(localized: "Valid coverage"), value: WorkoutFormat.duration(statistics.metricCoveredSeconds))
                        LabeledContent(String(localized: "Recorded samples"), value: String(localized: "Count: \(statistics.metricSampleCount)"))
                        if metric.id == "speed", workout.sportKind == .running {
                            LabeledContent(String(localized: "Average pace"), value: WorkoutFormat.pace(statistics.metricStatistics.averageValue))
                            LabeledContent(String(localized: "Fastest sample pace"), value: WorkoutFormat.pace(statistics.metricStatistics.maximumValue))
                        }
                    } else {
                        Text("Derived statistics are unavailable. Return to workout details to retry the analysis.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if let statistics {
                    AnalysisCard(title: "Distribution", color: metric.accent) {
                        Chart(Array(statistics.metricDistribution.enumerated()), id: \.offset) { _, bin in
                            RectangleMark(xStart: .value(metric.unit, bin.binLower * metric.canonicalScale),
                                    xEnd: .value(metric.unit, bin.binUpper * metric.canonicalScale),
                                    yStart: .value("Minutes", 0),
                                    yEnd: .value("Minutes", bin.binSeconds / 60))
                                .foregroundStyle(metric.accent.gradient)
                        }.frame(height: 220)
                        Text("Horizontal axis: \(metric.unit) · Vertical axis: minutes. Weighted by covered time, not sample count.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if let analysis {
                    if metric.id == "power", !analysis.analysisPowerZones.isEmpty {
                        AnalysisCard(title: "Power zones", color: .purple) {
                            ZoneChart(zones: analysis.analysisPowerZones, unit: "W")
                            Text("Zone boundaries are 55%, 75%, 90%, 105%, 120% and 150% of threshold power. Only valid power coverage is included.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    ForEach(Array(analysis.analysisRelationships.filter { $0.relationshipX.rawValue == metric.id + "Metric" }.enumerated()), id: \.offset) { _, relationship in
                        if let other = comparisonMetrics.first(where: { $0.id + "Metric" == relationship.relationshipY.rawValue }) {
                            RelationshipCard(metric: metric, other: other, relationship: relationship)
                        }
                    }
                }
            }.padding(20).frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .background(FitnessStyle.background).navigationTitle(String(localized: "\(metric.localizedTitle) analysis")).navigationBarTitleDisplayMode(.inline)
        .task(id: workout.workoutId + ":" + workout.workoutRevision) { comparisonMetrics = workout.metrics }
        .onChange(of: axis) { _, _ in selection = nil }
    }
}

private struct RelationshipCard: View {
    let metric: WorkoutMetric
    let other: WorkoutMetric
    let relationship: Components.Schemas.MetricRelationship
    var body: some View {
        AnalysisCard(title: "\(metric.localizedTitle) and \(other.localizedTitle)", color: metric.accent) {
            Chart(Array(relationship.relationshipPoints.enumerated()), id: \.offset) { _, point in
                PointMark(x: .value(metric.unit, point.relationshipXValue * metric.canonicalScale),
                          y: .value(other.unit, point.relationshipYValue * other.canonicalScale))
                    .foregroundStyle(metric.accent.opacity(0.5)).symbolSize(12)
            }.frame(height: 220)
                .chartXAxisLabel(metric.localizedTitle + " · " + metric.unit)
                .chartYAxisLabel(other.localizedTitle + " · " + other.unit)
            analysisRow("Correlation", relationship.relationshipCorrelation, "", digits: 2)
            Text("Aligned sample pairs: \(relationship.relationshipSampleCount); the chart shows up to 600 pairs. Correlation does not imply causation.")
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

    private struct ProjectionKey: Equatable {
        let workout: String
        let revision: String
        let metric: String
        let axis: MetricAxis
    }
    private struct Prepared {
        let key: ProjectionKey
        let projection: MetricChartProjection
        let domain: ClosedRange<Double>
    }
    @State private var prepared: Prepared?
    private var key: ProjectionKey {
        ProjectionKey(workout: workout.workoutId, revision: workout.workoutRevision, metric: metric.id, axis: axis)
    }

    var body: some View {
        let current = prepared.flatMap { $0.key == key ? $0 : nil }
        let rendered = current?.projection.rendered ?? []
        let selected = selection?.wrappedValue ?? localSelection
        let nearest = selected.flatMap { current?.projection.nearest(to: $0) }
        VStack(alignment: .leading, spacing: 6) {
            if rendered.isEmpty { Text("No samples available for this axis").font(.caption).foregroundStyle(.secondary) }
            else {
                let chart = Chart {
                    ForEach(rendered) { point in
                        LineMark(x: .value(axis.localizedTitle, point.x), y: .value(metric.unit, point.value), series: .value("Continuous segment", point.segment))
                            .foregroundStyle(metric.accent).lineStyle(StrokeStyle(lineWidth: 2))
                        if point.isolated { PointMark(x: .value(axis.localizedTitle, point.x), y: .value(metric.unit, point.value)).foregroundStyle(metric.accent) }
                    }
                    if let nearest {
                        let x = nearest.x
                        RuleMark(x: .value(axis.localizedTitle, x)).foregroundStyle(.secondary.opacity(0.6))
                        PointMark(x: .value(axis.localizedTitle, x), y: .value(metric.unit, nearest.value)).foregroundStyle(metric.accent)
                    }
                }
                .chartXScale(domain: current?.domain ?? 0...1)
                .chartXSelection(value: selection ?? $localSelection)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let x = value.as(Double.self) { Text(axis == .time ? "\(Int(x / 60))′" : x.formatted(.number.precision(.fractionLength(1)))) }
                        }
                    }
                }
                .chartXAxisLabel(axis == .time ? String(localized: "Elapsed time (minutes)") : String(localized: "Distance (km)"))
                .accessibilityLabel("\(metric.localizedTitle) over \(axis.localizedTitle)")
                if let value = rendered.first?.value, rendered.allSatisfy({ $0.value == value }) {
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
                        + " · " + nearest.id.formatted(date: .omitted, time: .standard))
                        .font(.caption).monospacedDigit().foregroundStyle(metric.accent)
                }
            }
        }
        .task(id: key) {
            let distances = workout.motion.motionDistance
            let range = workout.workoutObservation.observationRange
            let domain: ClosedRange<Double> = axis == .time
                ? 0...max(1, range.rangeEnd.timeIntervalSince(range.rangeStart))
                : 0...max(0.001, (distances.map(\.value).max() ?? 0) / 1000)
            let projection = MetricChartProjection(metric: metric) { coordinate($0, distances: distances) }
            prepared = Prepared(key: key, projection: projection, domain: domain)
        }
    }

    private func coordinate(_ time: Date, distances: [Components.Schemas.Timed_Distance]) -> Double? {
        if axis == .time { return time.timeIntervalSince(workout.workoutObservation.observationRange.rangeStart) }
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
