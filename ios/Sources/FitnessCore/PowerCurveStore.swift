import Observation

@MainActor @Observable
public final class PowerCurveStore {
    public private(set) var curve: PowerCurve?
    public private(set) var isLoading = false
    public private(set) var message: ClientIssue?
    public private(set) var needsWorkoutRefresh = false
    @ObservationIgnored private let service: any PowerCurveService
    @ObservationIgnored private let session: SessionStore
    @ObservationIgnored private var generation: UInt64 = 0

    public init(service: any PowerCurveService, session: SessionStore) {
        self.service = service
        self.session = session
    }

    public func load(id: String, revision: String) async {
        generation &+= 1
        let request = generation
        let identity = session.generation
        curve = nil
        message = nil
        needsWorkoutRefresh = false
        guard let token = session.token, session.user != nil else { isLoading = false; return }
        isLoading = true
        defer { if generation == request { isLoading = false } }
        do {
            let result = try await service.powerCurve(token: token, id: id)
            guard generation == request, session.generation == identity else { return }
            try Task.checkCancellation()
            guard result.curveWorkoutId == id, result.inputRevision == revision else {
                needsWorkoutRefresh = true
                return
            }
            curve = result
        } catch {
            guard generation == request, session.generation == identity else { return }
            if (error as? APIResponseError)?.status == 401 { session.handleUnauthorized(for: identity) }
            else if !Task.isCancelled && !(error is CancellationError) { message = ClientIssue(error) }
        }
    }
}
