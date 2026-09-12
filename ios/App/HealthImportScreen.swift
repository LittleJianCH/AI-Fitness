import FitnessCore
import SwiftUI

@MainActor
struct HealthImportScreen: View {
    @State private var reader = HealthReader()
    @State private var store: HealthImportStore
    @State private var from = Date().addingTimeInterval(-30 * 86_400)
    @State private var to = Date()
    @State private var choices: [HealthWorkoutChoice] = []
    @State private var selected: Set<UUID> = []
    @State private var previews: [HealthImportPreview] = []
    @State private var isBusy = false
    @State private var hasRead = false
    @State private var message: String?
    @State private var action: Task<Void, Never>?

    init(api: FitnessAPI, session: SessionStore) {
        _store = State(initialValue: HealthImportStore(service: api, session: session))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("从苹果健康导入 AI Fitness")
                    Text("你选择的记录会发送到当前登录的后端。首先授权并选择骑行或跑步，再预览内容；确认后才上传。")
                        .font(.footnote).foregroundStyle(.secondary)
                    DatePicker("开始", selection: $from, in: ...to, displayedComponents: .date)
                        .disabled(isBusy)
                    DatePicker("结束", selection: $to, in: from...Date(), displayedComponents: .date)
                        .disabled(isBusy)
                    Button("授权并读取") { action = Task { await read() } }
                        .disabled(isBusy).accessibilityIdentifier("readHealthWorkouts")
                }
                Section {
                    Text("最多检查此期间最新的 200 条记录，只支持单项骑行和跑步，并排除本应用回写的记录。空列表可能与读取权限有关，并不代表没有运动。")
                        .font(.footnote).foregroundStyle(.secondary)
                    if hasRead, choices.isEmpty { Text("当前没有可显示的记录。可调整日期或在系统健康权限中检查。") }
                    ForEach(choices) { choice in
                        Button {
                            if selected.contains(choice.id) { selected.remove(choice.id) }
                            else if selected.count < 10 { selected.insert(choice.id) }
                            else { message = "每批最多选择 10 条运动，请分批导入。" }
                            previews = []
                        } label: {
                            HStack {
                                Image(systemName: selected.contains(choice.id) ? "checkmark.circle.fill" : "circle")
                                VStack(alignment: .leading) {
                                    Text(choice.sport == .cycling ? "骑行" : "跑步")
                                    Text(choice.start.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                                    Text(WorkoutFormat.duration(choice.duration)).font(.caption)
                                }
                            }
                        }.disabled(isBusy)
                    }
                    if !selected.isEmpty {
                        Button("预览已选 \(selected.count) 条") { action = Task { await prepare() } }
                            .disabled(isBusy)
                    }
                } header: { Text("选择运动") }
                if !previews.isEmpty {
                    Section {
                        Text("预览只包含可读取、关联于这条运动且来自同一来源的样本。缺失数据不会补算；区间样本显示在结束时刻，距离和能量累计可用增量。步数不推算为步频。暂不包含圈段、设备专有字段或其他运动类型。")
                            .font(.footnote).foregroundStyle(.secondary)
                        ForEach(previews) { preview in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(preview.observation.observationRange.rangeStart.formatted(date: .abbreviated, time: .shortened)).font(.headline)
                                Text("\(preview.sampleCount) 个样本")
                                DisclosureGroup("查看摘要及可用数据") {
                                    SummarySection(title: "苹果健康摘要", summary: preview.summary, isRunning: preview.isRunning)
                                    Text("心率 \(preview.motion.motionHeartRate.count) · 功率 \(preview.motion.motionPower.count) · 速度 \(preview.motion.motionSpeed.count) · 路线 \(preview.motion.motionPosition.count)")
                                        .font(.caption)
                                    RouteSection(positions: preview.motion.motionPosition)
                                }
                                if let message = store.messages[preview.id] { Text(message).font(.footnote) }
                                if let record = store.records[preview.id], record.status != .suppressed {
                                    if record.lastSuccess != nil {
                                        Button("更新已导入的关联数据") { upload(preview, intent: .refresh) }
                                            .disabled(isBusy)
                                    } else if record.status == .failed {
                                        Button("重试失败的导入") { upload(preview, intent: .retry) }
                                            .disabled(isBusy)
                                    }
                                }
                            }
                        }
                        Button("确认上传以上 \(previews.count) 条") {
                            action = Task {
                                isBusy = true
                                defer { isBusy = false }
                                for preview in previews {
                                    if Task.isCancelled { break }
                                    await store.upload(preview)
                                    if store.pauseBatch { break }
                                }
                            }
                        }.disabled(isBusy)
                    } header: { Text("预览与确认") }
                }
                if isBusy { ProgressView("正在处理…") }
                if let message { Text(message).foregroundStyle(.red) }
            }
            .navigationTitle("苹果健康")
            .onDisappear { action?.cancel() }
        }
    }

    private func read() async {
        isBusy = true; message = nil; previews = []; selected = []; choices = []
        defer { isBusy = false }
        do {
            try await reader.authorize()
            let calendar = Calendar.current
            let rangeEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: to)) ?? to
            choices = try await reader.workouts(from: calendar.startOfDay(for: from), to: rangeEnd)
            hasRead = true
        } catch { present(error) }
    }

    private func prepare() async {
        isBusy = true; message = nil; previews = []
        defer { isBusy = false }
        do {
            for choice in choices where selected.contains(choice.id) {
                let preview = try await reader.preview(id: choice.id)
                try Task.checkCancellation()
                previews.append(preview)
            }
        } catch { previews = []; present(error) }
    }

    private func upload(_ preview: HealthImportPreview, intent: HealthImportAction) {
        action = Task {
            isBusy = true
            defer { isBusy = false }
            await store.upload(preview, action: intent)
        }
    }

    private func present(_ error: any Error) {
        if error is CancellationError { return }
        message = (error as? HealthImportError)?.errorDescription ?? "无法读取苹果健康。请检查系统权限并重试。"
    }
}
