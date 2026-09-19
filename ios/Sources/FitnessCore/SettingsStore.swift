import Observation

@MainActor @Observable
public final class SettingsStore {
    public var settings: UserSettings? {
        sessionIdentity == session.generation ? cachedSettings : nil
    }
    private var cachedSettings: UserSettings?
    public private(set) var isLoading = false
    public private(set) var isSaving = false
    public private(set) var message: String?
    @ObservationIgnored private let service: any SettingsService
    @ObservationIgnored private let session: SessionStore
    @ObservationIgnored private var generation: UInt64 = 0
    private var sessionIdentity: UInt64?

    public init(service: any SettingsService, session: SessionStore) {
        self.service = service
        self.session = session
    }

    public func load() async {
        invalidateForSessionChange()
        guard !isSaving else { return }
        generation &+= 1
        let request = generation
        let identity = session.generation
        cachedSettings = nil
        message = nil
        guard let token = session.token, session.user != nil else { isLoading = false; return }
        isLoading = true
        defer { if generation == request { isLoading = false } }
        do {
            let result = try await service.settings(token: token)
            guard request == generation, identity == session.generation else { return }
            try Task.checkCancellation()
            cachedSettings = result
        } catch { handle(error, identity: identity, request: request) }
    }

    public func save(_ proposed: UserSettings) async -> Bool {
        invalidateForSessionChange()
        guard !isSaving, !isLoading, let token = session.token, session.user != nil else { return false }
        generation &+= 1
        let request = generation
        let identity = session.generation
        isSaving = true
        message = nil
        defer { if generation == request { isSaving = false } }
        do {
            let result = try await service.saveSettings(token: token, settings: proposed)
            guard request == generation, identity == session.generation else { return false }
            try Task.checkCancellation()
            cachedSettings = result
            return true
        } catch {
            handle(error, identity: identity, request: request)
            return false
        }
    }

    private func invalidateForSessionChange() {
        guard sessionIdentity != session.generation else { return }
        sessionIdentity = session.generation
        // Old requests must neither publish data nor finish the new account's work.
        generation &+= 1
        cachedSettings = nil
        message = nil
        isLoading = false
        isSaving = false
    }

    private func handle(_ error: any Error, identity: UInt64, request: UInt64) {
        guard request == generation, identity == session.generation else { return }
        if (error as? APIResponseError)?.status == 401 { session.handleUnauthorized(for: identity) }
        else if !Task.isCancelled && !(error is CancellationError) { message = userFacingError(error) }
    }
}
