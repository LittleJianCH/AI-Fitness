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
            ForEach(workout.metrics.filter { !$0.points.isEmpty }) { metric in
                MetricAnalysisCard(workout: workout, metric: metric,
                                   statistics: store.analysis?.analysisMetrics.first(where: { $0.metricKind.rawValue == metric.id + "Metric" }),
                                   analysis: store.analysis)
                if metric.id == "power" {
                    if let analysis = store.analysis { PowerSummaryCard(power: analysis.analysisPower) }
                    PowerCurveSection(workout: workout, api: api, session: session, refreshWorkout: refreshWorkout)
                }
            }
            if workout.motion.motionPower.isEmpty && (workout.recordedCommonSummary.summaryPower.averageValue != nil || workout.recordedCommonSummary.summaryPower.maximumValue != nil) {
                PowerCurveSection(workout: workout, api: api, session: session, refreshWorkout: refreshWorkout)
            }
            if let analysis = store.analysis {
                HeartLoadCard(heart: analysis.analysisHeart)
                NavigationLink {
                    TrainingHistoryScreen(api: api, session: session, ending: min(Date(), workout.workoutObservation.observationRange.rangeStart))
                } label: {
                    Label("Fitness and fatigue trends", systemImage: "chart.xyaxis.line")
                        .frame(maxWidth: .infinity, alignment: .leading).padding(20).fitnessCard()
                }
                if let running = analysis.analysisRunning { RunningDynamicsCard(running: running) }
                SplitAnalysisCard(sets: analysis.analysisSplits, halves: analysis.analysisHalves, isRunning: workout.sportKind == .running)
                DisclosureGroup("Analysis method and personal parameters") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Statistics and distributions are time-weighted, connecting samples at most 120 seconds apart. Zeros are retained; gaps are not filled with zeros.")
                        Text("Power connects samples at most 5 seconds apart. Normalized power uses complete 30-second rolling windows; interpret results under 10 minutes cautiously.")
                        Text("Splits and sensor averages use elapsed time, including stops. Heart rate load uses recorded timer events to exclude pauses when available.")
                        if let profile = analysis.analysisBodyProfile {
                            LabeledContent(String(localized: "Personal parameters effective from"), value: profile.bodyEffectiveFrom.formatted(date: .abbreviated, time: .shortened))
                        } else { Text("No personal parameters were effective at the workout start. Add them in Settings → Personal parameters.") }
                        LabeledContent(String(localized: "Algorithm"), value: analysis.analysisMethod)
                        LabeledContent(String(localized: "Parameter revision"), value: analysis.analysisSettingsRevision)
                    }.font(.footnote).foregroundStyle(.secondary).padding(.top, 12)
                }.padding(20).fitnessCard()
            } else if store.isLoading { ProgressView("Analyzing workout…").frame(maxWidth: .infinity) }
            if store.needsWorkoutRefresh {
                Label("The workout record changed. Reload details.", systemImage: "arrow.clockwise")
                Button("Reload details", action: refreshWorkout)
            }
            if let message = store.message {
                IssueText(message).foregroundStyle(.red)
                Button("Retry analysis") { retry = Task { await load() } }
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
    let statistics: MetricAnalysis?
    let analysis: WorkoutAnalysis?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            FitnessSectionTitle(title: metric.titleResource, color: metric.accent)
            VStack(alignment: .leading, spacing: 18) {
                if let statistics {
                    HStack(alignment: .top) {
                        if metric.id == "speed", workout.sportKind == .running {
                            FitnessStat(title: "Average pace", value: WorkoutFormat.pace(statistics.metricStatistics.averageValue), prominent: true)
                            FitnessStat(title: "Fastest sample pace", value: WorkoutFormat.pace(statistics.metricStatistics.maximumValue))
                        } else {
                            FitnessStat(title: "Average", value: metric.localizedValue(statistics.metricStatistics.averageValue), prominent: true)
                            FitnessStat(title: "Maximum", value: metric.localizedValue(statistics.metricStatistics.maximumValue))
                        }
                    }
                }
                MetricTimeline(workout: workout, metric: metric, axis: .time)
                    .frame(height: 165).accessibilityIdentifier("metric-\(metric.id)")
                HStack {
                    if let statistics {
                        Text("Valid coverage: \(WorkoutFormat.duration(statistics.metricCoveredSeconds))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    NavigationLink("Detailed analysis") {
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
        AnalysisCard(title: "Power analysis", color: .purple) {
            analysisRow("Normalized power", power.powerNormalized, "W")
            analysisRow("Variability index", power.powerVariabilityIndex, "", digits: 2)
            analysisRow("Intensity factor", power.powerIntensityFactor, "", digits: 2)
            analysisRow("Power training stress", power.powerStressScore, "", digits: 1)
            analysisRow("Average power / body weight", power.powerWattsPerKilogram, "W/kg", digits: 2)
            analysisRow("Observed mechanical work", power.powerWorkJoules.map { $0 / 1000 }, "kJ", digits: 1)
            analysisRow("Efficiency factor", power.powerEfficiency, "W/bpm", digits: 2)
            analysisRow("Power / heart rate decoupling between halves", power.powerDecouplingPercent, "%", digits: 1)
            Divider()
            analysisRow("Threshold power used", power.powerThresholdWatts, "W")
            analysisRow("Body weight used", power.powerAthleteKilograms, "kg", digits: 1)
            Text("Workout-recorded weight and threshold take precedence. Training stress, efficiency and decoupling require full coverage; unsupported results show no data.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}

private struct HeartLoadCard: View {
    let heart: Components.Schemas.HeartAnalysis
    private var status: String {
        switch heart.heartLoadStatus {
        case .heartLoadAvailable: String(localized: "Sample coverage meets the requirement")
        case .heartProfileMissing: String(localized: "Add heart rate parameters effective at the workout start in Settings")
        case .heartCoverageInsufficient: String(localized: "Heart rate coverage is below 95%; the load below covers only the observed portion")
        case .heartNoActiveTime: String(localized: "No valid timer duration")
        case .heartExcluded: String(localized: "This workout is excluded from statistics")
        case .heartCalculationUnavailable: String(localized: "Heart rate load cannot be calculated from the current data")
        }
    }
    var body: some View {
        AnalysisCard(title: "Heart rate and training load", color: .red) {
            Text(status).font(.subheadline).foregroundStyle(.secondary)
            analysisRow("HRSS", heart.heartHrss, "", digits: 1)
            analysisRow("TRIMPexp", heart.heartTrimp, "", digits: 1)
            analysisRow("Heart rate coverage", heart.heartCoverageFraction.map { $0 * 100 }, "%", digits: 1)
            LabeledContent(String(localized: "Timing basis"), value: heart.heartUsesRecordedTimer ? String(localized: "Recorded timer events") : String(localized: "Elapsed time"))
            if !heart.heartZones.isEmpty {
                ZoneChart(zones: heart.heartZones, unit: "bpm")
                Text("Zones use heart rate reserve boundaries of 50%, 60%, 70%, 80% and 90%. Z0 is below 50%; Z6 is at or above the configured maximum heart rate. Readings above maximum are excluded from load.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

private struct RunningDynamicsCard: View {
    let running: Components.Schemas.RunningAnalysis
    var body: some View {
        AnalysisCard(title: "Running dynamics", color: .orange) {
            analysisRow("Steps (complete cadence integral)", running.runningSteps, String(localized: "steps"))
            analysisRow("Flight time", running.runningFlightSeconds.map { $0 * 1000 }, "ms")
            analysisRow("Vertical ratio", running.runningVerticalRatioPercent, "%", digits: 1)
            analysisRow("Flight ratio", running.runningFlightRatioPercent, "%", digits: 1)
            analysisRow("Running effectiveness", running.runningEffectiveness, "", digits: 2)
            Text("Flight time uses cadence and ground contact time. Vertical ratio uses vertical oscillation and step length. Simultaneous valid samples are required.")
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
        AnalysisCard(title: "Distance splits", color: .blue) {
            Picker("Split length", selection: $length) {
                Text("1 km").tag(1000.0)
                Text("5 km").tag(5000.0)
            }.pickerStyle(.segmented)
            if splits.isEmpty {
                Text("Continuous, increasing distance samples are required for splits. Gaps and distance resets are not extrapolated.")
                    .foregroundStyle(.secondary)
            } else {
                Chart(splits.prefix(100), id: \.splitIndex) { split in
                    BarMark(x: .value("Split", String(split.splitIndex)), y: .value("km/h", split.splitAverageSpeed * 3.6))
                        .foregroundStyle(.blue.gradient)
                }.frame(height: 140)
                NavigationLink("View all splits (\(splits.count))") {
                    List(splits, id: \.splitIndex) { split in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Split \(split.splitIndex)").font(.headline)
                                Spacer()
                                Text(WorkoutFormat.distance(split.splitDistanceMetres))
                            }
                            LabeledContent(String(localized: "Duration"), value: WorkoutFormat.duration(split.splitEndSeconds - split.splitStartSeconds))
                            LabeledContent(isRunning ? String(localized: "Pace") : String(localized: "Speed"), value: isRunning ? WorkoutFormat.pace(split.splitAverageSpeed) : WorkoutFormat.number(split.splitAverageSpeed * 3.6, unit: "km/h", fractionDigits: 1))
                            analysisRow("Heart rate", split.splitHeartRate, "bpm")
                            analysisRow("Power", split.splitPower, "W")
                            analysisRow(isRunning ? "Running cadence" : "Cycling cadence", split.splitCadence, isRunning ? String(localized: "steps/min") : "rpm")
                            analysisRow("Net elevation change", split.splitElevationChange, "m")
                        }.padding(.vertical, 8)
                    }.navigationTitle("\(Int(length / 1000)) km splits")
                }.accessibilityIdentifier("distanceSplits")
            }
            if let halves {
                Divider()
                LabeledContent(String(localized: "First half"), value: speed(halves.firstHalfSpeed))
                LabeledContent(String(localized: "Second half"), value: speed(halves.secondHalfSpeed))
                analysisRow("Speed change in the second half", halves.secondHalfChangePercent, "%", digits: 1)
            }
            Text("Uses elapsed time, including stops. The final split retains its actual distance.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
    private func speed(_ value: Double) -> String { isRunning ? WorkoutFormat.pace(value) : WorkoutFormat.number(value * 3.6, unit: "km/h", fractionDigits: 1) }
}

struct ZoneChart: View {
    let zones: [Components.Schemas.ZoneDuration]
    let unit: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Chart(zones, id: \.zoneIndex) { zone in
                BarMark(x: .value("Minutes", zone.zoneSeconds / 60), y: .value("Zone", "Z\(zone.zoneIndex)"))
                    .foregroundStyle(by: .value("Zone", "Z\(zone.zoneIndex)"))
            }.chartLegend(.hidden).frame(height: 190)
            ForEach(zones, id: \.zoneIndex) { zone in
                HStack {
                    Text("Z\(zone.zoneIndex)").fontWeight(.semibold)
                    Text(zone.zoneUpper.map { "\(WorkoutFormat.number(zone.zoneLower, unit: ""))–\(WorkoutFormat.number($0, unit: unit))" } ?? String(localized: "\(WorkoutFormat.number(zone.zoneLower, unit: unit)) and above"))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(WorkoutFormat.duration(zone.zoneSeconds)).monospacedDigit()
                }.font(.caption)
            }
        }
    }
}

struct AnalysisCard<Content: View>: View {
    let title: LocalizedStringResource
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

@MainActor
func analysisRow(_ title: LocalizedStringResource, _ value: Double?, _ unit: String, digits: Int = 0) -> some View {
    LabeledContent { Text(WorkoutFormat.number(value, unit: unit, fractionDigits: digits)) } label: { LocalizedText(title) }
        .monospacedDigit()
        .accessibilityElement(children: .combine)
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
