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
    @State private var message: String?
    @State private var completed = false
    @State private var confirming = false
    @State private var plan: HealthExportPlan?
    @State private var quantityCount = 0

    private static let coordinator = HealthExportCoordinator(journal: FileHealthExportJournal(
        directory: URL.applicationSupportDirectory.appendingPathComponent("HealthExports", isDirectory: true)))

    var body: some View {
        NavigationStack {
            Form {
                Section("导出预览") {
                    Text((plan?.workout ?? workout).displayTitle)
                    Text("版本 \((plan?.workout ?? workout).workoutRevision)")
                    if let plan, plan.workout.workoutRevision != workout.workoutRevision {
                        Text("先恢复此前确认的版本，再重新打开此页面导出当前版本。")
                    }
                    LabeledContent("路线点", value: String((plan?.workout ?? workout).motion.motionPosition.count))
                    LabeledContent("测量样本", value: String(quantityCount))
                    LabeledContent("记录距离", value: WorkoutFormat.distance((plan?.workout ?? workout).recordedCommonSummary.summaryDistance))
                    Text(HealthExportPlan.projectionNotice).font(.footnote)
                }
                Section {
                    Button(completed ? "已完成导出" : "写入 Apple 健康 / 恢复导出") { confirming = true }
                        .disabled(busy || completed || plan == nil)
                        .accessibilityIdentifier("confirmHealthExport")
                    if busy { ProgressView("正在处理导出…") }
                    if let message { Text(message).accessibilityIdentifier("healthExportResult") }
                } footer: {
                    Text("中途离开后，可从此运动详情重新打开并恢复。仅在平台写入和后端回执都确认后显示完成。")
                }
            }
            .navigationTitle("导出到 Apple 健康")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() }.accessibilityIdentifier("closeHealthExport") } }
            .confirmationDialog("确认将预览的数据写入 Apple 健康？", isPresented: $confirming, titleVisibility: .visible) {
                Button("确认写入") { action = Task { await perform() } }
            }
        }
        .task {
            do {
                guard let user = session.user else { return }
                let requested = try HealthExportPlan(workout: workout, origin: api.endpoint.credentialScope, ownerID: user.id)
                let resumed = try await Self.coordinator.planToResume(requested)
                quantityCount = try resumed.quantities().count
                plan = resumed
            } catch { message = (error as? HealthExportError)?.errorDescription ?? userFacingError(error) }
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
            message = "Apple 健康写入与后端回执均已确认。"
        } catch {
            guard session.generation == identity, !(error is CancellationError) else { return }
            if (error as? APIResponseError)?.status == 401 { session.handleUnauthorized(for: identity) }
            else { message = (error as? HealthExportError)?.errorDescription ?? (error as? HealthWriterError)?.errorDescription ?? userFacingError(error) }
        }
    }
}
