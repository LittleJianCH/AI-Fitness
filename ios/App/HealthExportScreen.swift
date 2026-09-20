import FitnessCore
import SwiftUI

@MainActor
struct HealthExportScreen: View {
    @Environment(\.dismiss) private var dismiss
    let workout: Workout
    let api: FitnessAPI
    let session: SessionStore
    @State private var action: Task<Void, Never>?
    @State private var busy = false
    @State private var message: LocalizedStringResource?
    @State private var completed = false
    @State private var confirming = false
    @State private var plan: HealthExportPlan?
    @State private var quantityCount = 0

    private static let coordinator = HealthExportCoordinator(journal: FileHealthExportJournal(
        directory: URL.applicationSupportDirectory.appendingPathComponent("HealthExports", isDirectory: true)))

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    FitnessIntro(title: "Save to Apple Health", subtitle: "Confirm the version and data to export. If interrupted, return here to resume.", symbol: "heart.fill", color: .pink)
                }.listRowBackground(Color.clear)
                Section("Export preview") {
                    Text((plan?.workout ?? workout).displayTitle)
                    Text("Revision \((plan?.workout ?? workout).workoutRevision)")
                    if let plan, plan.workout.workoutRevision != workout.workoutRevision {
                        Text("Resume the previously confirmed version first, then reopen this page to export the current revision.")
                    }
                    LabeledContent(String(localized: "Route points"), value: String((plan?.workout ?? workout).motion.motionPosition.count))
                    LabeledContent(String(localized: "Measurement samples"), value: String(quantityCount))
                    LabeledContent(String(localized: "Recorded distance"), value: WorkoutFormat.distance((plan?.workout ?? workout).recordedCommonSummary.summaryDistance))
                }
                Section {
                    DisclosureGroup("What the export includes") {
                        LocalizedText(HealthExportPlan.projectionNotice).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section {
                    Button(completed ? String(localized: "Export completed") : String(localized: "Write to Apple Health / Resume export")) { confirming = true }
                        .buttonStyle(.borderedProminent).tint(.pink).controlSize(.large)
                        .disabled(busy || completed || plan == nil)
                        .accessibilityIdentifier("confirmHealthExport")
                    if busy { ProgressView("Processing export…") }
                    if let message { LocalizedText(message).accessibilityIdentifier("healthExportResult") }
                } footer: {
                    Text("If interrupted, reopen export from this workout to resume. Completion requires both the platform write and the server receipt to be confirmed.")
                }
            }
            .scrollContentBackground(.hidden).background(FitnessStyle.background)
            .navigationTitle("Export to Apple Health")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.accessibilityIdentifier("closeHealthExport") } }
            .confirmationDialog("Write the previewed data to Apple Health?", isPresented: $confirming, titleVisibility: .visible) {
                Button("Confirm write") { action = Task { await perform() } }
            }
        }
        .task {
            do {
                guard let user = session.user else { return }
                let requested = try HealthExportPlan(workout: workout, origin: api.endpoint.credentialScope, ownerID: user.id)
                let resumed = try await Self.coordinator.planToResume(requested)
                quantityCount = try resumed.quantities().count
                plan = resumed
            } catch { message = ClientIssue(error).resource }
        }
        .onDisappear { action?.cancel() }
    }

    private func perform() async {
        guard !busy, let token = session.token, session.user != nil, let plan else { return }
        let identity = session.generation
        busy = true
        message = nil
        defer { busy = false }
        do {
            _ = try plan.quantities()
            _ = try await Self.coordinator.export(plan, token: token, service: api, writer: HealthWriter())
            guard session.generation == identity, !Task.isCancelled else { return }
            completed = true
            message = "The Apple Health write and server receipt are both confirmed."
        } catch {
            guard session.generation == identity, !(error is CancellationError) else { return }
            if (error as? APIResponseError)?.status == 401 { session.handleUnauthorized(for: identity) }
            else { message = (error as? HealthWriterError)?.resource ?? ClientIssue(error).resource }
        }
    }
}
