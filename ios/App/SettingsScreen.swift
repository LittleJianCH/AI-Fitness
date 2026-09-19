import ContractClient
import FitnessCore
import SwiftUI

@MainActor
struct SettingsScreen<Account: View>: View {
    let store: SettingsStore
    let server: String
    @ViewBuilder let account: () -> Account

    var body: some View {
        NavigationStack {
            List {
                Section {
                    FitnessIntro(title: "设置", subtitle: "你的偏好、身体参数与运动器材。", symbol: "slider.horizontal.3")
                }.listRowBackground(Color.clear)
                if let settings = store.settings {
                    Section {
                        NavigationLink { SoftwareSettingsScreen(store: store, server: server) } label: {
                            Label("软件设置", systemImage: "gearshape")
                        }
                        NavigationLink { BodySettingsScreen(store: store) } label: {
                            Label("个人身体参数", systemImage: "person.text.rectangle")
                        }.accessibilityIdentifier("bodySettings")
                        NavigationLink { EquipmentSettingsScreen(store: store) } label: {
                            Label("器材", systemImage: "bicycle")
                        }.accessibilityIdentifier("equipmentSettings")
                    } footer: {
                        Text("已保存到当前账号 · 版本 \(settings.settingsRevision)")
                    }
                } else if store.isLoading {
                    ProgressView("正在加载设置…")
                }
                if let message = store.message {
                    Section {
                        Text(message).foregroundStyle(.red)
                        Button("重新加载") { Task { await store.load() } }.disabled(store.isSaving)
                    }
                }
                Section { NavigationLink("账号与登录会话", destination: account) }
            }
            .scrollContentBackground(.hidden).background(FitnessStyle.background)
            .navigationTitle("设置")
            .refreshable { await store.load() }
        }
    }
}

@MainActor
private struct SoftwareSettingsScreen: View {
    let store: SettingsStore
    let server: String
    @State private var action: Task<Void, Never>?

    var body: some View {
        Form {
            if let settings = store.settings {
                Section("外观") {
                    Picker("主题", selection: Binding(get: { settings.settingsSoftware.softwareAppearance }, set: { appearance in
                        var updated = settings
                        updated.settingsSoftware.softwareAppearance = appearance
                        action = Task { _ = await store.save(updated) }
                    })) {
                        Text("跟随系统").tag(Components.Schemas.Appearance.systemAppearance)
                        Text("浅色").tag(Components.Schemas.Appearance.lightAppearance)
                        Text("深色").tag(Components.Schemas.Appearance.darkAppearance)
                    }.disabled(store.isSaving)
                }
            }
            Section("连接") { LabeledContent("服务器", value: server) }
            Section("显示") {
                LabeledContent("单位", value: "公制 · km / kg / W")
                LabeledContent("时区", value: TimeZone.current.identifier)
            }
            if store.isSaving { ProgressView("正在保存…") }
            if let message = store.message { Text(message).foregroundStyle(.red) }
        }
        .navigationTitle("软件设置").navigationBarTitleDisplayMode(.inline)
        .onDisappear { action?.cancel() }
    }
}

@MainActor
private struct BodySettingsScreen: View {
    let store: SettingsStore
    @State private var editing = false

    var body: some View {
        List {
            Section {
                Text("记录体重、身高，以及骑行和跑步各自的功率与心率阈值。缺少的参数可以留空。")
                    .foregroundStyle(.secondary)
                Button("更新个人参数") { editing = true }.accessibilityIdentifier("editBodyParameters")
            } footer: {
                Text("每次更新都新增一条带生效时间的记录。分析优先使用运动中的身体参数；缺少时使用运动开始时生效的个人参数。")
            }
            if let profiles = store.settings?.settingsBodyProfiles {
                ForEach(profiles.reversed(), id: \.bodyProfileId) { profile in
                    Section(profile.bodyEffectiveFrom.formatted(date: .abbreviated, time: .shortened)) {
                        LabeledContent("体重", value: WorkoutFormat.number(profile.bodyMassKilograms, unit: "kg", fractionDigits: 1))
                        LabeledContent("身高", value: WorkoutFormat.number(profile.bodyHeightMetres.map { $0 * 100 }, unit: "cm", fractionDigits: 1))
                        sportSummary("骑行", profile.bodyCycling)
                        sportSummary("跑步", profile.bodyRunning)
                    }
                }
            }
        }
        .navigationTitle("个人身体参数").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $editing) {
            if let settings = store.settings { BodyProfileEditor(store: store, original: settings) }
        }
    }

    @ViewBuilder private func sportSummary(_ title: String, _ profile: SportProfile) -> some View {
        LabeledContent("\(title)阈值功率", value: WorkoutFormat.number(profile.sportThresholdWatts, unit: "W"))
        if let hr = profile.sportHeartRate {
            LabeledContent("\(title)静息 / 阈值 / 最大心率", value: "\(hr.heartRateResting.formatted()) / \(hr.heartRateThreshold.formatted()) / \(hr.heartRateMaximum.formatted())")
        }
    }
}

private struct SportDraft {
    var watts = ""
    var resting = ""
    var threshold = ""
    var maximum = ""
    var weighting = Components.Schemas.LoadWeighting.exponent192

    init(_ profile: SportProfile?) {
        watts = fieldText(profile?.sportThresholdWatts)
        resting = fieldText(profile?.sportHeartRate?.heartRateResting)
        threshold = fieldText(profile?.sportHeartRate?.heartRateThreshold)
        maximum = fieldText(profile?.sportHeartRate?.heartRateMaximum)
        weighting = profile?.sportHeartRate?.heartRateWeighting ?? .exponent192
    }

    func value() throws -> SportProfile {
        let values = try [resting, threshold, maximum].map(parseOptionalPositive)
        let hr: HeartRateProfile?
        if values.allSatisfy({ $0 == nil }) { hr = nil }
        else if let resting = values[0], let threshold = values[1], let maximum = values[2], resting < threshold, threshold <= maximum {
            hr = .init(heartRateMaximum: maximum, heartRateResting: resting, heartRateThreshold: threshold, heartRateWeighting: weighting)
        } else { throw FormError.message("心率参数请全部填写，并满足：静息心率 < 阈值心率 ≤ 最大心率。") }
        return try .init(sportHeartRate: hr, sportThresholdWatts: parseOptionalPositive(watts))
    }
}

private struct SportParameterFields: View {
    let title: String
    let identifier: String
    @Binding var draft: SportDraft

    var body: some View {
        Section(title) {
            numberField("阈值功率 (W)", identifier: "\(identifier)-watts", text: $draft.watts)
            numberField("静息心率 (bpm)", identifier: "\(identifier)-resting", text: $draft.resting)
            numberField("阈值心率 (bpm)", identifier: "\(identifier)-threshold", text: $draft.threshold)
            numberField("最大心率 (bpm)", identifier: "\(identifier)-maximum", text: $draft.maximum)
            Picker("TRIMP 指数", selection: $draft.weighting) {
                Text("1.92").tag(Components.Schemas.LoadWeighting.exponent192)
                Text("1.67").tag(Components.Schemas.LoadWeighting.exponent167)
            }
            Text("负荷使用你选择的指数；不会根据身份推断。心率区间按心率储备划分。")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}

@MainActor
private struct BodyProfileEditor: View {
    let store: SettingsStore
    let original: UserSettings
    @Environment(\.dismiss) private var dismiss
    @State private var mass: String
    @State private var height: String
    @State private var cycling: SportDraft
    @State private var running: SportDraft
    @State private var effectiveFrom = Date()
    @State private var error: String?
    @State private var action: Task<Void, Never>?

    init(store: SettingsStore, original: UserSettings) {
        self.store = store
        self.original = original
        let last = original.settingsBodyProfiles.last
        _mass = State(initialValue: fieldText(last?.bodyMassKilograms))
        _height = State(initialValue: fieldText(last?.bodyHeightMetres.map { $0 * 100 }))
        _cycling = State(initialValue: SportDraft(last?.bodyCycling))
        _running = State(initialValue: SportDraft(last?.bodyRunning))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("身体参数") {
                    numberField("体重 (kg)", identifier: "bodyMass", text: $mass)
                    numberField("身高 (cm)", identifier: "bodyHeight", text: $height)
                    DatePicker("生效时间", selection: $effectiveFrom)
                }
                Section {
                    Text("生效时间之前的运动保持原参数。选择较早的时间，会使该时间之后的运动采用这次填写的参数进行分析。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                SportParameterFields(title: "骑行", identifier: "cycling", draft: $cycling)
                SportParameterFields(title: "跑步", identifier: "running", draft: $running)
                if let error { Text(error).foregroundStyle(.red) }
                if let message = store.message { Text(message).foregroundStyle(.red) }
                if store.isSaving { ProgressView("正在保存…") }
            }
            .navigationTitle("更新个人参数").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(store.isSaving) }
                ToolbarItem(placement: .confirmationAction) { Button("保存", action: save).disabled(store.isSaving).accessibilityIdentifier("saveBodyParameters") }
            }
            .interactiveDismissDisabled(store.isSaving)
        }.onDisappear { action?.cancel() }
    }

    private func save() {
        do {
            error = nil
            if let previous = original.settingsBodyProfiles.last, effectiveFrom <= previous.bodyEffectiveFrom {
                throw FormError.message("生效时间需要晚于上一条参数记录。")
            }
            let profile = try BodyProfile(bodyCycling: cycling.value(), bodyEffectiveFrom: effectiveFrom,
                bodyHeightMetres: parseOptionalPositive(height).map { $0 / 100 }, bodyMassKilograms: parseOptionalPositive(mass),
                bodyProfileId: UUID().uuidString, bodyRunning: running.value())
            var updated = original
            updated.settingsBodyProfiles.append(profile)
            action = Task { if await store.save(updated) { dismiss() } }
        } catch { self.error = (error as? FormError)?.text ?? "请检查填写内容。" }
    }
}

@MainActor
private struct EquipmentSettingsScreen: View {
    let store: SettingsStore
    @State private var editor: EquipmentEditorSelection?

    var body: some View {
        List {
            Section {
                Button { editor = EquipmentEditorSelection(equipment: nil) } label: { Label("添加器材", systemImage: "plus") }
                    .accessibilityIdentifier("addEquipment")
            }
            ForEach(store.settings?.settingsEquipment ?? [], id: \.equipmentId) { equipment in
                Button { editor = EquipmentEditorSelection(equipment: equipment) } label: {
                    HStack {
                        Label(equipment.equipmentName, systemImage: equipment.equipmentKind == .bicycle ? "bicycle" : "shoeprints.fill")
                        Spacer()
                        if equipment.equipmentRetired { Text("已停用").foregroundStyle(.secondary) }
                    }
                }.foregroundStyle(.primary)
            }
        }
        .navigationTitle("器材").navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editor) { selection in
            if let settings = store.settings { EquipmentEditor(store: store, original: settings, equipment: selection.equipment) }
        }
    }
}

private struct EquipmentEditorSelection: Identifiable {
    let id = UUID()
    let equipment: Equipment?
}

@MainActor
private struct EquipmentEditor: View {
    let store: SettingsStore
    let original: UserSettings
    let equipment: Equipment?
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var mass: String
    @State private var kind: Components.Schemas.EquipmentKind
    @State private var retired: Bool
    @State private var error: String?
    @State private var action: Task<Void, Never>?

    init(store: SettingsStore, original: UserSettings, equipment: Equipment?) {
        self.store = store
        self.original = original
        self.equipment = equipment
        _name = State(initialValue: equipment?.equipmentName ?? "")
        _mass = State(initialValue: fieldText(equipment?.equipmentMassKilograms))
        _kind = State(initialValue: equipment?.equipmentKind ?? .bicycle)
        _retired = State(initialValue: equipment?.equipmentRetired ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("器材名称", text: $name).accessibilityIdentifier("equipmentName")
                Picker("类型", selection: $kind) {
                    Text("自行车").tag(Components.Schemas.EquipmentKind.bicycle)
                    Text("跑鞋").tag(Components.Schemas.EquipmentKind.runningShoes)
                }.disabled(equipment != nil)
                numberField("重量 (kg，可选)", identifier: "equipmentMass", text: $mass)
                Toggle("停用器材", isOn: $retired)
                if let error { Text(error).foregroundStyle(.red) }
                if let message = store.message { Text(message).foregroundStyle(.red) }
                if store.isSaving { ProgressView("正在保存…") }
            }
            .navigationTitle(equipment == nil ? "添加器材" : "编辑器材").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(store.isSaving) }
                ToolbarItem(placement: .confirmationAction) { Button("保存", action: save).disabled(store.isSaving).accessibilityIdentifier("saveEquipment") }
            }
            .interactiveDismissDisabled(store.isSaving)
        }.onDisappear { action?.cancel() }
    }

    private func save() {
        do {
            error = nil
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.count <= 120 else { throw FormError.message("请填写不超过 120 字的器材名称。") }
            let entry = try Equipment(equipmentId: equipment?.equipmentId ?? UUID().uuidString,
                equipmentKind: kind, equipmentMassKilograms: parseOptionalPositive(mass), equipmentName: trimmed, equipmentRetired: retired)
            var updated = original
            if let index = updated.settingsEquipment.firstIndex(where: { $0.equipmentId == entry.equipmentId }) { updated.settingsEquipment[index] = entry }
            else { updated.settingsEquipment.append(entry) }
            action = Task { if await store.save(updated) { dismiss() } }
        } catch { self.error = (error as? FormError)?.text ?? "请检查填写内容。" }
    }
}

private enum FormError: Error {
    case message(String)
    var text: String { switch self { case .message(let text): text } }
}

private func fieldText(_ value: Double?) -> String {
    value.map { $0.formatted(.number.grouping(.never).precision(.fractionLength(0...3))) } ?? ""
}

private func parseOptionalPositive(_ text: String) throws -> Double? {
    guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
    guard let value = try? Double(text, format: .number), value.isFinite, value > 0 else {
        throw FormError.message("数值需要大于零；没有数据时请留空。")
    }
    return value
}

private func numberField(_ title: String, identifier: String, text: Binding<String>) -> some View {
    LabeledContent(title) {
        TextField("未设置", text: text).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
            .frame(minWidth: 70).accessibilityIdentifier(identifier)
    }
}
