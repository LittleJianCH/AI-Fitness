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
    @State private var message: LocalizedStringResource?
    @State private var action: Task<Void, Never>?

    init(api: FitnessAPI, session: SessionStore) {
        _store = State(initialValue: HealthImportStore(service: api, session: session))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    FitnessIntro(title: "Import from Apple Health", subtitle: "Select cycling or running workouts, then review and confirm uploading to the current server.", symbol: "heart.fill", color: .pink)
                }.listRowBackground(Color.clear)
                Section {
                    DatePicker("Start", selection: $from, in: ...to, displayedComponents: .date)
                        .disabled(isBusy)
                    DatePicker("End", selection: $to, in: from...Date(), displayedComponents: .date)
                        .disabled(isBusy)
                    Button { action = Task { await read() } } label: {
                        Text("Authorize and read").multilineTextAlignment(.center).frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 4)
                    }
                        .buttonStyle(.borderedProminent).tint(.pink).controlSize(.large)
                        .buttonBorderShape(.roundedRectangle(radius: 14))
                        .disabled(isBusy).accessibilityIdentifier("readHealthWorkouts")
                } header: { Text("Date range") }
                Section {
                    Text("Checks up to the latest 200 records in this period. Only single-sport cycling and running are supported; records written by this app are excluded. An empty list may reflect read permissions rather than no workouts.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if hasRead, choices.isEmpty { Text("No records are available to display. Adjust the dates or check system Health permissions.") }
                    ForEach(choices) { choice in
                        Button {
                            if selected.contains(choice.id) { selected.remove(choice.id) }
                            else if selected.count < 10 { selected.insert(choice.id) }
                            else { message = "Select up to 10 workouts per batch." }
                            previews = []
                        } label: {
                            HStack {
                                Image(systemName: selected.contains(choice.id) ? "checkmark.circle.fill" : "circle")
                                VStack(alignment: .leading) {
                                    Text(choice.sport == .cycling ? String(localized: "Cycling") : String(localized: "Running"))
                                    Text(choice.start.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                                    Text(WorkoutFormat.duration(choice.duration)).font(.caption)
                                }
                            }
                        }.disabled(isBusy)
                    }
                    if !selected.isEmpty {
                        Button("Preview selection (\(selected.count))") { action = Task { await prepare() } }
                            .disabled(isBusy)
                    }
                } header: { Text("Select workouts") }
                if !previews.isEmpty {
                    Section {
                        Text("The preview includes readable samples associated with this workout and from the same source. Missing data are not estimated. Interval samples use their end time; distance and energy accumulate available increments. Step counts are not converted to cadence. Laps, device-specific fields and other sports are not included.")
                            .font(.footnote).foregroundStyle(.secondary)
                        ForEach(previews) { preview in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(preview.observation.observationRange.rangeStart.formatted(date: .abbreviated, time: .shortened)).font(.headline)
                                Text("Samples: \(preview.sampleCount)")
                                DisclosureGroup("View summary and available data") {
                                    SummarySection(title: "Apple Health summary", summary: preview.summary, isRunning: preview.isRunning, inCard: false)
                                    Text("Heart rate \(preview.motion.motionHeartRate.count) · Power \(preview.motion.motionPower.count) · Speed \(preview.motion.motionSpeed.count) · Route \(preview.motion.motionPosition.count)")
                                        .font(.caption)
                                    RouteSection(positions: preview.motion.motionPosition, inCard: false)
                                }
                                if let message = store.messages[preview.id] { IssueText(message).font(.footnote) }
                                if let record = store.records[preview.id], record.status != .suppressed {
                                    if record.lastSuccess != nil {
                                        Button("Refresh linked imported data") { upload(preview, intent: .refresh) }
                                            .disabled(isBusy)
                                    } else if record.status == .failed {
                                        Button("Retry failed import") { upload(preview, intent: .retry) }
                                            .disabled(isBusy)
                                    }
                                }
                            }
                        }
                        Button("Confirm upload (\(previews.count))") {
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
                    } header: { Text("Preview and confirm") }
                }
                if isBusy { ProgressView("Processing…") }
                if let message { LocalizedText(message).foregroundStyle(.red) }
            }
            .listStyle(.insetGrouped).scrollContentBackground(.hidden).background(FitnessStyle.background)
            .navigationTitle("Apple Health")
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
        message = ClientIssue(error).resource
    }
}
