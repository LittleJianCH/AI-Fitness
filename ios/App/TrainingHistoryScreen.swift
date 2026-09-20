import Charts
import ContractClient
import FitnessCore
import SwiftUI

@MainActor
struct TrainingHistoryScreen: View {
    @State private var store: TrainingHistoryStore
    @State private var endDate: Date
    @State private var count = 90
    @State private var complete = false
    @State private var zeroInitial = false
    @State private var initialFitness = ""
    @State private var initialFatigue = ""
    @State private var inputError: LocalizedStringResource?
    @State private var action: Task<Void, Never>?

    init(api: FitnessAPI, session: SessionStore, ending: Date) {
        _store = State(initialValue: TrainingHistoryStore(service: api, session: session))
        _endDate = State(initialValue: ending)
    }

    var body: some View {
        Form {
            Section("History range") {
                DatePicker("End date", selection: $endDate, in: ...Date(), displayedComponents: .date)
                Picker("Days", selection: $count) {
                    Text("42 days").tag(42)
                    Text("90 days").tag(90)
                    Text("180 days").tag(180)
                }
                Text("Dates use \(TimeZone.current.identifier). Workouts belong to their start date; today's result updates as new records arrive.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Toggle("All workouts in this range have been imported", isOn: $complete)
            } footer: {
                Text("When confirmed, days without workouts count as rest. Otherwise they remain unknown, so missing records are not treated as zero load.")
            }
            Section {
                Toggle("Assume no training load before the start", isOn: $zeroInitial)
                    .accessibilityIdentifier("assumeNoPriorLoad")
                if !zeroInitial {
                    TextField("Initial fitness CTL", text: $initialFitness).keyboardType(.decimalPad)
                    TextField("Initial fatigue ATL", text: $initialFatigue).keyboardType(.decimalPad)
                }
            } header: { Text("Initial state") } footer: {
                Text("If you have CTL / ATL from the same HRSS model, enter the values for the day before this range. A zero start is a calculation assumption that strongly affects short histories.")
            }
            Section {
                Button("Calculate fitness and fatigue", action: load).disabled(store.isLoading)
                    .accessibilityIdentifier("calculateTrainingHistory")
                if store.isLoading { ProgressView("Calculating…") }
                if let inputError { LocalizedText(inputError).foregroundStyle(.red) }
                if let message = store.message { IssueText(message).foregroundStyle(.red) }
            }
            if let history = store.history {
                Section("Training trends") {
                    if history.trainingDays.contains(where: { $0.trainingFitness != nil || $0.trainingFatigue != nil }) {
                        Chart(history.trainingDays, id: \.trainingCalendar.calendarDate) { day in
                            if let fitness = day.trainingFitness {
                                LineMark(x: .value("Date", day.trainingCalendar.calendarStart), y: .value("HRSS / day", fitness), series: .value("Metric", String(localized: "Fitness CTL")))
                                    .foregroundStyle(by: .value("Metric", String(localized: "Fitness CTL")))
                            }
                            if let fatigue = day.trainingFatigue {
                                LineMark(x: .value("Date", day.trainingCalendar.calendarStart), y: .value("HRSS / day", fatigue), series: .value("Metric", String(localized: "Fatigue ATL")))
                                    .foregroundStyle(by: .value("Metric", String(localized: "Fatigue ATL")))
                            }
                        }.frame(height: 240)
                    } else {
                        Label("No training trend available", systemImage: "chart.xyaxis.line")
                            .foregroundStyle(.secondary)
                        Text("Confirm complete workout records and configure heart rate parameters. Training load remains unknown when heart rate sampling is insufficient.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if let last = history.trainingDays.last {
                        analysisRow("Ending fitness CTL", last.trainingFitness, "", digits: 1)
                        analysisRow("Ending fatigue ATL", last.trainingFatigue, "", digits: 1)
                        analysisRow("Training balance CTL − ATL", last.trainingBalance, "", digits: 1)
                        analysisRow("Remaining influence of the initial CTL", last.trainingInitialFitnessWeight * 100, "%", digits: 1)
                    }
                    Text("Fitness uses 42-day and fatigue uses 7-day exponential decay. These HRSS values cannot be directly compared with other load models.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Daily load") {
                    ForEach(history.trainingDays.reversed(), id: \.trainingCalendar.calendarDate) { day in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(day.trainingCalendar.calendarDate)
                                Spacer()
                                Text(WorkoutFormat.number(day.trainingTotalLoad, unit: "HRSS", fractionDigits: 1)).monospacedDigit()
                            }
                            Text("\(day.trainingWorkoutCount) workouts · Known load \(WorkoutFormat.number(day.trainingKnownLoad, unit: "", fractionDigits: 1))")
                                .font(.caption).foregroundStyle(.secondary)
                            if day.trainingTotalLoad == nil { Text("Record completeness, heart rate coverage or personal parameters are insufficient. This day and subsequent trends remain unknown.")
                                .font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
        }
        .navigationTitle("Fitness and fatigue").navigationBarTitleDisplayMode(.inline)
        .onDisappear { action?.cancel() }
    }

    private func load() {
        inputError = nil
        let fitness = NumericInput.parse(initialFitness)
        let fatigue = NumericInput.parse(initialFatigue)
        if !zeroInitial && !(fitness.map { $0.isFinite && $0 >= 0 } == true && fatigue.map { $0.isFinite && $0 >= 0 } == true) {
            inputError = "Select the zero-start assumption or enter nonnegative initial CTL and ATL values."
            return
        }
        let input = TrainingHistoryRequest(historyAssumeNoPriorLoad: zeroInitial,
            historyCalendar: TrainingCalendar.days(ending: endDate, count: count, timeZone: .current, complete: complete),
            historyPriorFatigue: zeroInitial ? nil : fatigue, historyPriorFitness: zeroInitial ? nil : fitness)
        action?.cancel()
        action = Task { await store.load(input) }
    }
}
