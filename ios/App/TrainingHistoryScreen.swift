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
    @State private var inputError: String?
    @State private var action: Task<Void, Never>?

    init(api: FitnessAPI, session: SessionStore, ending: Date) {
        _store = State(initialValue: TrainingHistoryStore(service: api, session: session))
        _endDate = State(initialValue: ending)
    }

    var body: some View {
        Form {
            Section("历史范围") {
                DatePicker("结束日期", selection: $endDate, in: ...Date(), displayedComponents: .date)
                Picker("天数", selection: $count) {
                    Text("42 天").tag(42)
                    Text("90 天").tag(90)
                    Text("180 天").tag(180)
                }
                Text("日期按 \(TimeZone.current.identifier) 划分。当天的运动计入开始日期；今天的结果会随新记录更新。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Toggle("这段历史中的运动均已导入", isOn: $complete)
            } footer: {
                Text("确认后，没有运动的日子按休息日计算。未确认时保留未知状态，避免把漏记的运动当作零负荷。")
            }
            Section {
                Toggle("假设开始前没有训练负荷", isOn: $zeroInitial)
                    .accessibilityIdentifier("assumeNoPriorLoad")
                if !zeroInitial {
                    TextField("初始体能 CTL", text: $initialFitness).keyboardType(.decimalPad)
                    TextField("初始疲劳 ATL", text: $initialFatigue).keyboardType(.decimalPad)
                }
            } header: { Text("初始状态") } footer: {
                Text("若已有同一 HRSS 模型下的 CTL / ATL，可填写范围开始前一天的值。零起点仅是计算假设，短历史会明显受它影响。")
            }
            Section {
                Button("计算体能与疲劳", action: load).disabled(store.isLoading)
                    .accessibilityIdentifier("calculateTrainingHistory")
                if store.isLoading { ProgressView("正在计算…") }
                if let message = inputError ?? store.message { Text(message).foregroundStyle(.red) }
            }
            if let history = store.history {
                Section("训练趋势") {
                    Chart(history.trainingDays, id: \.trainingCalendar.calendarDate) { day in
                        if let fitness = day.trainingFitness {
                            LineMark(x: .value("日期", day.trainingCalendar.calendarStart), y: .value("HRSS / 日", fitness), series: .value("指标", "体能 CTL"))
                                .foregroundStyle(by: .value("指标", "体能 CTL"))
                        }
                        if let fatigue = day.trainingFatigue {
                            LineMark(x: .value("日期", day.trainingCalendar.calendarStart), y: .value("HRSS / 日", fatigue), series: .value("指标", "疲劳 ATL"))
                                .foregroundStyle(by: .value("指标", "疲劳 ATL"))
                        }
                    }.frame(height: 240)
                    if let last = history.trainingDays.last {
                        analysisRow("期末体能 CTL", last.trainingFitness, "", digits: 1)
                        analysisRow("期末疲劳 ATL", last.trainingFatigue, "", digits: 1)
                        analysisRow("负荷平衡 CTL − ATL", last.trainingBalance, "", digits: 1)
                        analysisRow("起点对当前 CTL 的剩余影响", last.trainingInitialFitnessWeight * 100, "%", digits: 1)
                    }
                    Text("体能使用 42 天、疲劳使用 7 天的指数衰减。基于 HRSS，不能与其他负荷模型的数值直接比较。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("每日负荷") {
                    ForEach(history.trainingDays.reversed(), id: \.trainingCalendar.calendarDate) { day in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(day.trainingCalendar.calendarDate)
                                Spacer()
                                Text(WorkoutFormat.number(day.trainingTotalLoad, unit: "HRSS", fractionDigits: 1)).monospacedDigit()
                            }
                            Text("\(day.trainingWorkoutCount) 次运动 · 已知负荷 " + WorkoutFormat.number(day.trainingKnownLoad, unit: "", fractionDigits: 1))
                                .font(.caption).foregroundStyle(.secondary)
                            if day.trainingTotalLoad == nil { Text("记录完整性、心率覆盖或个人参数不足，此日及后续趋势保留未知。")
                                .font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
        }
        .navigationTitle("体能与疲劳").navigationBarTitleDisplayMode(.inline)
        .onDisappear { action?.cancel() }
    }

    private func load() {
        inputError = nil
        let fitness = try? Double(initialFitness, format: .number)
        let fatigue = try? Double(initialFatigue, format: .number)
        if !zeroInitial && !(fitness.map { $0.isFinite && $0 >= 0 } == true && fatigue.map { $0.isFinite && $0 >= 0 } == true) {
            inputError = "请选择零起点假设，或填写非负的初始 CTL 和 ATL。"
            return
        }
        let input = TrainingHistoryRequest(historyAssumeNoPriorLoad: zeroInitial,
            historyCalendar: TrainingCalendar.days(ending: endDate, count: count, timeZone: .current, complete: complete),
            historyPriorFatigue: zeroInitial ? nil : fatigue, historyPriorFitness: zeroInitial ? nil : fitness)
        action?.cancel()
        action = Task { await store.load(input) }
    }
}
