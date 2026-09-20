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
                    FitnessIntro(title: "Settings", subtitle: "Your preferences, personal parameters and sports equipment.", symbol: "slider.horizontal.3")
                }.listRowBackground(Color.clear)
                if let settings = store.settings {
                    Section {
                        NavigationLink { SoftwareSettingsScreen(store: store, server: server) } label: {
                            Label("Software settings", systemImage: "gearshape")
                        }
                        NavigationLink { BodySettingsScreen(store: store) } label: {
                            Label("Personal parameters", systemImage: "person.text.rectangle")
                        }.accessibilityIdentifier("bodySettings")
                        NavigationLink { EquipmentSettingsScreen(store: store) } label: {
                            Label("Equipment", systemImage: "bicycle")
                        }.accessibilityIdentifier("equipmentSettings")
                    } footer: {
                        Text("Saved to this account · Revision \(settings.settingsRevision)")
                    }
                } else if store.isLoading {
                    ProgressView("Loading settings…")
                }
                if let message = store.message {
                    Section {
                        IssueText(message).foregroundStyle(.red)
                        Button("Reload") { Task { await store.load() } }.disabled(store.isSaving)
                    }
                }
                Section { NavigationLink("Account and sign-in sessions", destination: account) }
            }
            .scrollContentBackground(.hidden).background(FitnessStyle.background)
            .navigationTitle("Settings")
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
                Section("Appearance") {
                    Picker("Theme", selection: Binding(get: { settings.settingsSoftware.softwareAppearance }, set: { appearance in
                        var updated = settings
                        updated.settingsSoftware.softwareAppearance = appearance
                        action = Task { _ = await store.save(updated) }
                    })) {
                        Text("System").tag(Components.Schemas.Appearance.systemAppearance)
                        Text("Light").tag(Components.Schemas.Appearance.lightAppearance)
                        Text("Dark").tag(Components.Schemas.Appearance.darkAppearance)
                    }.disabled(store.isSaving || store.isLoading)
                }
            }
            Section("Connect") { LabeledContent(String(localized: "Server"), value: server) }
            Section("Display") {
                LabeledContent(String(localized: "Units"), value: String(localized: "Metric · km / kg / W"))
                LabeledContent(String(localized: "Time zone"), value: TimeZone.current.identifier)
            }
            if store.isSaving { ProgressView("Saving…") }
            if let message = store.message { IssueText(message).foregroundStyle(.red) }
        }
        .navigationTitle("Software settings").navigationBarTitleDisplayMode(.inline)

    }
}

@MainActor
private struct BodySettingsScreen: View {
    let store: SettingsStore
    @State private var editing = false

    var body: some View {
        List {
            Section {
                Text("Record weight, height, and separate power and heart rate thresholds for cycling and running. Leave unknown parameters empty.")
                    .foregroundStyle(.secondary)
                Button("Update personal parameters") { editing = true }.accessibilityIdentifier("editBodyParameters")
            } footer: {
                Text("Each update creates a record with an effective time. Analysis uses workout-recorded parameters first, then personal parameters effective at the workout start.")
            }
            if let profiles = store.settings?.settingsBodyProfiles {
                ForEach(profiles.reversed(), id: \.bodyProfileId) { profile in
                    Section(profile.bodyEffectiveFrom.formatted(date: .abbreviated, time: .shortened)) {
                        LabeledContent(String(localized: "Body weight"), value: WorkoutFormat.number(profile.bodyMassKilograms, unit: "kg", fractionDigits: 1))
                        LabeledContent(String(localized: "Height"), value: WorkoutFormat.number(profile.bodyHeightMetres.map { $0 * 100 }, unit: "cm", fractionDigits: 1))
                        sportSummary(String(localized: "Cycling"), profile.bodyCycling)
                        sportSummary(String(localized: "Running"), profile.bodyRunning)
                    }
                }
            }
        }
        .navigationTitle("Personal parameters").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $editing) {
            if let settings = store.settings { BodyProfileEditor(store: store, original: settings) }
        }
    }

    @ViewBuilder private func sportSummary(_ title: String, _ profile: SportProfile) -> some View {
        LabeledContent(String(localized: "\(title) threshold power"), value: WorkoutFormat.number(profile.sportThresholdWatts, unit: "W"))
        if let hr = profile.sportHeartRate {
            LabeledContent(String(localized: "\(title) resting / threshold / maximum heart rate"), value: "\(hr.heartRateResting.formatted()) / \(hr.heartRateThreshold.formatted()) / \(hr.heartRateMaximum.formatted())")
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
        } else { throw FormError.message("Complete all heart rate parameters, with resting < threshold ≤ maximum heart rate.") }
        return try .init(sportHeartRate: hr, sportThresholdWatts: parseOptionalPositive(watts))
    }
}

private struct SportParameterFields: View {
    let title: LocalizedStringResource
    let identifier: String
    @Binding var draft: SportDraft

    var body: some View {
        Section {
            NumberField("Threshold power (W)", identifier: "\(identifier)-watts", text: $draft.watts)
            NumberField("Resting heart rate (bpm)", identifier: "\(identifier)-resting", text: $draft.resting)
            NumberField("Threshold heart rate (bpm)", identifier: "\(identifier)-threshold", text: $draft.threshold)
            NumberField("Maximum heart rate (bpm)", identifier: "\(identifier)-maximum", text: $draft.maximum)
            Picker("TRIMP coefficient", selection: $draft.weighting) {
                Text("1.92").tag(Components.Schemas.LoadWeighting.exponent192)
                Text("1.67").tag(Components.Schemas.LoadWeighting.exponent167)
            }
            Text("Load uses your selected coefficient, without inferring it from your identity. Heart rate zones use heart rate reserve.")
                .font(.footnote).foregroundStyle(.secondary)
        } header: { LocalizedText(title) }
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
    @State private var error: LocalizedStringResource?
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
                Section("Body parameters") {
                    NumberField("Body weight (kg)", identifier: "bodyMass", text: $mass)
                    NumberField("Height (cm)", identifier: "bodyHeight", text: $height)
                    DatePicker("Effective from", selection: $effectiveFrom)
                }
                Section {
                    Text("Earlier workouts retain their previous parameters. An earlier effective date applies these parameters to analysis of workouts starting from that time.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                SportParameterFields(title: "Cycling", identifier: "cycling", draft: $cycling)
                SportParameterFields(title: "Running", identifier: "running", draft: $running)
                if let error { LocalizedText(error).foregroundStyle(.red) }
                if let message = store.message { IssueText(message).foregroundStyle(.red) }
                if store.isSaving { ProgressView("Saving…") }
            }
            .navigationTitle("Edit parameters").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(store.isSaving) }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(store.isSaving || store.isLoading).accessibilityIdentifier("saveBodyParameters") }
            }
            .interactiveDismissDisabled(store.isSaving)
        }
    }

    private func save() {
        do {
            error = nil
            if let previous = original.settingsBodyProfiles.last, effectiveFrom <= previous.bodyEffectiveFrom {
                throw FormError.message("The effective time must be after the previous parameter record.")
            }
            let profile = try BodyProfile(bodyCycling: cycling.value(), bodyEffectiveFrom: effectiveFrom,
                bodyHeightMetres: parseOptionalPositive(height).map { $0 / 100 }, bodyMassKilograms: parseOptionalPositive(mass),
                bodyProfileId: UUID().uuidString, bodyRunning: running.value())
            var updated = original
            updated.settingsBodyProfiles.append(profile)
            action = Task { if await store.save(updated) { dismiss() } }
        } catch { self.error = (error as? FormError)?.text ?? "Check the form." }
    }
}

@MainActor
private struct EquipmentSettingsScreen: View {
    let store: SettingsStore
    @State private var editor: EquipmentEditorSelection?

    var body: some View {
        List {
            Section {
                Button { editor = EquipmentEditorSelection(equipment: nil) } label: { Label("Add equipment", systemImage: "plus") }
                    .accessibilityIdentifier("addEquipment")
            }
            ForEach(store.settings?.settingsEquipment ?? [], id: \.equipmentId) { equipment in
                Button { editor = EquipmentEditorSelection(equipment: equipment) } label: {
                    HStack {
                        Label(equipment.equipmentName, systemImage: equipment.equipmentKind == .bicycle ? "bicycle" : "shoeprints.fill")
                        Spacer()
                        if equipment.equipmentRetired { Text("Retired").foregroundStyle(.secondary) }
                    }
                }.foregroundStyle(.primary)
            }
        }
        .navigationTitle("Equipment").navigationBarTitleDisplayMode(.inline)
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
    @State private var error: LocalizedStringResource?
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
                TextField("Equipment name", text: $name).accessibilityIdentifier("equipmentName")
                Picker("Type", selection: $kind) {
                    Text("Bike").tag(Components.Schemas.EquipmentKind.bicycle)
                    Text("Running shoes").tag(Components.Schemas.EquipmentKind.runningShoes)
                }.disabled(equipment != nil)
                NumberField("Weight (kg, optional)", identifier: "equipmentMass", text: $mass)
                Toggle("Retire equipment", isOn: $retired)
                if let error { LocalizedText(error).foregroundStyle(.red) }
                if let message = store.message { IssueText(message).foregroundStyle(.red) }
                if store.isSaving { ProgressView("Saving…") }
            }
            .navigationTitle(equipment == nil ? String(localized: "Add equipment") : String(localized: "Edit equipment")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(store.isSaving) }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(store.isSaving || store.isLoading).accessibilityIdentifier("saveEquipment") }
            }
            .interactiveDismissDisabled(store.isSaving)
        }
    }

    private func save() {
        do {
            error = nil
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.count <= 120 else { throw FormError.message("Enter an equipment name of at most 120 characters.") }
            let entry = try Equipment(equipmentId: equipment?.equipmentId ?? UUID().uuidString,
                equipmentKind: kind, equipmentMassKilograms: parseOptionalPositive(mass), equipmentName: trimmed, equipmentRetired: retired)
            var updated = original
            if let index = updated.settingsEquipment.firstIndex(where: { $0.equipmentId == entry.equipmentId }) { updated.settingsEquipment[index] = entry }
            else { updated.settingsEquipment.append(entry) }
            action = Task { if await store.save(updated) { dismiss() } }
        } catch { self.error = (error as? FormError)?.text ?? "Check the form." }
    }
}

private enum FormError: Error {
    case message(LocalizedStringResource)
    var text: LocalizedStringResource { switch self { case .message(let text): text } }
}

private func fieldText(_ value: Double?) -> String {
    value.map { $0.formatted(.number.grouping(.never).precision(.fractionLength(0...3))) } ?? ""
}

private func parseOptionalPositive(_ text: String) throws -> Double? {
    guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
    guard let value = NumericInput.parse(text), value > 0 else {
        throw FormError.message("Values must be greater than zero. Leave missing data empty.")
    }
    return value
}

@MainActor
private struct NumberField: View {
    let title: LocalizedStringResource
    let identifier: String
    @Binding var text: String
    @Environment(\.locale) private var locale

    init(_ title: LocalizedStringResource, identifier: String, text: Binding<String>) {
        self.title = title
        self.identifier = identifier
        _text = text
    }

    var body: some View {
        var localizedTitle = title
        localizedTitle.locale = locale
        // An explicit row lets Form measure multiline labels at their full height.
        // LabeledContent's native row can clip a wrapped label to one line.
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(localizedTitle).lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
            TextField("Not set", text: $text)
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                .frame(minWidth: 70, maxWidth: 120)
                .accessibilityLabel(Text(localizedTitle))
                .accessibilityIdentifier(identifier)
        }
    }
}
