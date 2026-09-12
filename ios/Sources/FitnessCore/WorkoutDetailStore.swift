import Observation

@MainActor @Observable
public final class WorkoutDetailStore {
    public private(set) var workout: Workout?
    public private(set) var isLoading = false
    public private(set) var message: String?
    @ObservationIgnored private let service: any WorkoutService
    @ObservationIgnored private let session: SessionStore
    @ObservationIgnored private var generation: UInt64 = 0

    public init(service: any WorkoutService, session: SessionStore) {
        self.service = service
        self.session = session
    }

    public func load(id: String) async {
        guard let token = session.token, session.user != nil else { return }
        generation &+= 1
        let request = generation
        let identity = session.generation
        workout = nil
        isLoading = true
        message = nil
        defer { if generation == request { isLoading = false } }
        do {
            let result = try await service.workout(token: token, id: id)
            guard generation == request, session.generation == identity else { return }
            try Task.checkCancellation()
            workout = result
        } catch {
            guard generation == request, session.generation == identity else { return }
            if (error as? APIResponseError)?.status == 401 { session.handleUnauthorized(for: identity) }
            else if !(error is CancellationError) { message = userFacingError(error) }
        }
    }
}
