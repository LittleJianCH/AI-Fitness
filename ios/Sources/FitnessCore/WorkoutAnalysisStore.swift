import Observation

@MainActor @Observable
public final class WorkoutAnalysisStore {
    public private(set) var analysis: WorkoutAnalysis?
    public private(set) var isLoading = false
    public private(set) var message: ClientIssue?
    public private(set) var needsWorkoutRefresh = false
    @ObservationIgnored private let service: any WorkoutAnalysisService
    @ObservationIgnored private let session: SessionStore
    @ObservationIgnored private var generation: UInt64 = 0

    public init(service: any WorkoutAnalysisService, session: SessionStore) {
        self.service = service
        self.session = session
    }

    public func load(id: String, revision: String) async {
        generation &+= 1
        let request = generation
        let identity = session.generation
        analysis = nil
        message = nil
        needsWorkoutRefresh = false
        guard let token = session.token, session.user != nil else { isLoading = false; return }
        isLoading = true
        defer { if request == generation { isLoading = false } }
        do {
            let result = try await service.workoutAnalysis(token: token, id: id)
            guard request == generation, identity == session.generation else { return }
            try Task.checkCancellation()
            guard result.analysisWorkoutId == id, result.analysisRevision == revision else {
                needsWorkoutRefresh = true
                return
            }
            analysis = result
        } catch {
            guard request == generation, identity == session.generation else { return }
            if (error as? APIResponseError)?.status == 401 { session.handleUnauthorized(for: identity) }
            else if Task.isCancelled || error is CancellationError { message = .analysisCancelled }
            else { message = ClientIssue(error) }
        }
    }
}
