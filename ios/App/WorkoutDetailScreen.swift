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
                    SummarySection(title: "Recorded summary", summary: workout.recordedCommonSummary, isRunning: workout.sportKind == .running)
                    RouteSection(positions: workout.motion.motionPosition)
                    WorkoutAnalysisSection(workout: workout, api: api, session: session, refreshWorkout: reloadWorkout)
                        .id(curveReload)
                    RecordedDetailsSection(workout: workout)
                    if workout.metrics.contains(where: { $0.points.isEmpty }) {
                        DisclosureGroup("Unrecorded metrics") {
                            ForEach(workout.metrics.filter { $0.points.isEmpty }) { metric in
                                LabeledContent(metric.localizedTitle, value: String(localized: "No sample data")).padding(.vertical, 6)
                            }
                        }.font(.subheadline).foregroundStyle(.secondary).padding(20).fitnessCard()
                    }
                    if let calculated = workout.calculatedCommonSummary {
                        DisclosureGroup("Server-calculated summary") {
                            SummarySection(title: "Calculated results", summary: calculated, isRunning: workout.sportKind == .running, inCard: false).padding(.top, 12)
                        }.padding(20).fitnessCard()
                    }
                    if workout.workoutUserData.workoutNotes != nil || !workout.workoutUserData.workoutTags.isEmpty || workout.workoutUserData.statisticsInclusion == .excludeFromStatistics {
                        VStack(alignment: .leading, spacing: 14) {
                            FitnessSectionTitle(title: "Workout notes")
                            VStack(alignment: .leading, spacing: 14) {
                                if let notes = workout.workoutUserData.workoutNotes { Text(notes).textSelection(.enabled) }
                                if !workout.workoutUserData.workoutTags.isEmpty {
                                    Label(workout.workoutUserData.workoutTags.joined(separator: " · "), systemImage: "tag")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                }
                                if workout.workoutUserData.statisticsInclusion == .excludeFromStatistics {
                                    Label("This record is excluded from statistics", systemImage: "chart.bar.xaxis").font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(20).fitnessCard()
                        }
                    }
                    if !workout.workoutObservation.observationDataIssues.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            FitnessSectionTitle(title: "About the data")
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(Array(workout.workoutObservation.observationDataIssues.enumerated()), id: \.offset) { _, issue in
                                    Label(issue.issueDescription, systemImage: "info.circle").font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(20).fitnessCard()
                        }
                    }
                } else if store.isLoading {
                    ProgressView("Loading details…").frame(maxWidth: .infinity).padding(40)
                }
                if let message = store.message {
                    VStack(alignment: .leading, spacing: 12) {
                        IssueText(message).foregroundStyle(.red)
                        Button("Retry", action: reloadWorkout).buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(20).fitnessCard()
                }
            }
            .frame(maxWidth: 760).padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 32)
            .frame(maxWidth: .infinity)
        }
        .background(FitnessStyle.background)
        .navigationTitle("Workout details").navigationBarTitleDisplayMode(.inline)
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
        let running = workout.sportKind == .running
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
                .accessibilityLabel("Export to Apple Health").accessibilityIdentifier("openHealthExport")
            }
            Text(workout.displayTitle).font(.largeTitle.bold()).accessibilityIdentifier("workoutTitle")
            VStack(alignment: .leading, spacing: 5) {
                Text(workout.workoutObservation.observationRange.rangeStart.formatted(date: .abbreviated, time: .standard))
                Text("Until \(workout.workoutObservation.observationRange.rangeEnd.formatted(date: .abbreviated, time: .standard))")
            }.font(.subheadline).foregroundStyle(.secondary)
            Text("Device time zone · \(TimeZone.current.identifier)").font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

struct SummarySection: View {
    let title: LocalizedStringResource
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
                FitnessStat(title: "Distance", value: WorkoutFormat.distance(summary.summaryDistance), prominent: true)
                FitnessStat(title: "Timer time", value: WorkoutFormat.duration(summary.summaryTimerTime), prominent: true)
            }
            DisclosureGroup {
                VStack(spacing: 16) {
                    LabeledContent(String(localized: "Elapsed time"), value: WorkoutFormat.duration(summary.summaryElapsedTime))
                    LabeledContent(String(localized: "Moving time"), value: WorkoutFormat.duration(summary.summaryMovingTime))
                    LabeledContent(String(localized: "Average heart rate"), value: WorkoutFormat.number(summary.summaryHeartRate.averageValue, unit: "bpm"))
                    LabeledContent(String(localized: "Average power"), value: WorkoutFormat.number(summary.summaryPower.averageValue, unit: "W"))
                    LabeledContent(String(localized: "Average speed"), value: WorkoutFormat.number(summary.summarySpeed.averageValue.map { $0 * 3.6 }, unit: "km/h", fractionDigits: 1))
                    if isRunning { LabeledContent(String(localized: "Average pace"), value: WorkoutFormat.pace(summary.summarySpeed.averageValue)) }
                    LabeledContent(String(localized: "Ascent"), value: WorkoutFormat.number(summary.summaryAscent, unit: "m"))
                }.font(.body).foregroundStyle(.primary).monospacedDigit().padding(.top, 16)
            } label: {
                Text("More summary metrics").frame(minHeight: 44)
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
            FitnessSectionTitle(title: "Route", color: .blue)
            if positions.isEmpty {
                Label("No route data", systemImage: "map")
                    .font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(inCard ? 20 : 0)
                    .background(inCard ? FitnessStyle.surface : Color.clear, in: RoundedRectangle(cornerRadius: FitnessStyle.radius, style: .continuous))
            } else {
                VStack(spacing: 0) {
                    WorkoutRouteMap(positions: positions)
                    .frame(height: 270).accessibilityLabel("Recorded workout route")
                    HStack {
                        Button { fullScreen = true } label: { Label("Expand map", systemImage: "arrow.up.left.and.arrow.down.right") }
                            .accessibilityIdentifier("expandRoute")
                        Spacer()
                        Text("Route points: \(positions.count)").monospacedDigit()
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
                    .navigationTitle("Workout route").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { fullScreen = false } } }
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
                Marker("Route start", coordinate: .init(latitude: first.value.latitude, longitude: first.value.longitude)).tint(.green)
            }
            if let last = positions.last {
                Marker("Finish", coordinate: .init(latitude: last.value.latitude, longitude: last.value.longitude)).tint(.red)
            }
        }
        .mapStyle(satellite ? .hybrid : .standard)
        .overlay(alignment: .topTrailing) {
            if controls {
                Button(satellite ? String(localized: "Standard map") : String(localized: "Satellite map")) { satellite.toggle() }
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
        AnalysisCard(title: "Elevation, energy and environment", color: .teal) {
            analysisRow("Total ascent", summary.summaryAscent, "m")
            analysisRow("Total descent", summary.summaryDescent, "m")
            analysisRow("Minimum altitude", summary.summaryAltitude.minimumValue, "m")
            analysisRow("Maximum altitude", summary.summaryAltitude.maximumValue, "m")
            analysisRow("Metabolic energy", summary.summaryMetabolicEnergy.map { $0 / 4184 }, "kcal")
            analysisRow("Mechanical work", summary.summaryMechanicalWork.map { $0 / 1000 }, "kJ")
            analysisRow("Average temperature", summary.summaryTemperature.averageValue, "°C", digits: 1)
            Text("These are source-recorded summaries. Metabolic energy and mechanical work are shown separately; missing metrics are not estimated.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        if !laps.isEmpty {
            AnalysisCard(title: "Device-recorded laps") {
                NavigationLink("View recorded laps (\(laps.count))") {
                    List(laps) { lap in
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Lap \(lap.id + 1)").font(.headline)
                            Text(lap.range.rangeStart.formatted(date: .omitted, time: .standard) + "–" + lap.range.rangeEnd.formatted(date: .omitted, time: .standard)).font(.caption).foregroundStyle(.secondary)
                            LabeledContent(String(localized: "Distance"), value: WorkoutFormat.distance(lap.summary.summaryDistance))
                            LabeledContent(String(localized: "Timer time"), value: WorkoutFormat.duration(lap.summary.summaryTimerTime))
                            analysisRow("Average power", lap.summary.summaryPower.averageValue, "W")
                            analysisRow("Average heart rate", lap.summary.summaryHeartRate.averageValue, "bpm")
                            if workout.sportKind == .running {
                                LabeledContent(String(localized: "Average pace"), value: WorkoutFormat.pace(lap.summary.summarySpeed.averageValue))
                            } else {
                                analysisRow("Average speed", lap.summary.summarySpeed.averageValue.map { $0 * 3.6 }, "km/h", digits: 1)
                            }
                        }.padding(.vertical, 8)
                    }.navigationTitle("Device laps")
                }
            }
        }
        if case .case1(let sport) = workout.workoutObservation.observationSport {
            let context = sport.data.cyclingContext
            if context.bicycleName != nil || context.bicycleMass != nil || context.cyclingDiscipline != nil {
                AnalysisCard(title: "Workout equipment") {
                    if let name = context.bicycleName { LabeledContent(String(localized: "Bike"), value: name) }
                    if let discipline = context.cyclingDiscipline { LabeledContent(String(localized: "Cycling type"), value: discipline) }
                    analysisRow("Bike weight", context.bicycleMass, "kg", digits: 1)
                }
            }
        }
    }
}
