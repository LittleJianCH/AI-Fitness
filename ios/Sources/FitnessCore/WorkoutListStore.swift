import Foundation
import Observation

@MainActor @Observable
public final class WorkoutListStore {
    public private(set) var items: [WorkoutCard] = []
    public private(set) var nextCursor: String?
    public private(set) var isLoading = false
    public private(set) var hasLoaded = false
    public private(set) var message: String?
    public private(set) var sport: WorkoutSportFilter?
    @ObservationIgnored private let service: any WorkoutService
    @ObservationIgnored private let session: SessionStore
    @ObservationIgnored private var requestGeneration: UInt64 = 0

    public init(service: any WorkoutService, session: SessionStore) {
        self.service = service
        self.session = session
    }

    public func refresh(sport: WorkoutSportFilter?) async {
        requestGeneration &+= 1
        let request = requestGeneration
        let changedFilter = self.sport != sport
        self.sport = sport
        if changedFilter { items = []; hasLoaded = false }
        nextCursor = nil
        await load(cursor: nil, request: request, replacing: true)
    }

    public func loadIfNeeded(sport: WorkoutSportFilter?) async {
        // Navigation reappearance must retain accumulated pages and scroll rows.
        if !hasLoaded || self.sport != sport { await refresh(sport: sport) }
    }

    public func loadMore() async {
        guard !isLoading, let nextCursor else { return }
        requestGeneration &+= 1
        await load(cursor: nextCursor, request: requestGeneration, replacing: false)
    }

    private func load(cursor: String?, request: UInt64, replacing: Bool) async {
        guard let token = session.token, session.user != nil else { return }
        let identity = session.generation
        isLoading = true
        message = nil
        defer { if requestGeneration == request { isLoading = false } }
        do {
            let page = try await service.workouts(token: token, sport: sport, cursor: cursor)
            guard requestGeneration == request, session.generation == identity else { return }
            try Task.checkCancellation()
            var rows = replacing ? [] : items
            // Pagination is not a historical snapshot. Preserve order, replacing
            // repeated identities with their latest returned resource view.
            var positions = Dictionary(uniqueKeysWithValues: rows.enumerated().map { ($0.element.id, $0.offset) })
            for row in page.items {
                if let index = positions[row.id] { rows[index] = row }
                else { positions[row.id] = rows.count; rows.append(row) }
            }
            items = rows
            nextCursor = page.nextCursor
            hasLoaded = true
        } catch {
            guard requestGeneration == request, session.generation == identity else { return }
            if (error as? APIResponseError)?.status == 401 { session.handleUnauthorized(for: identity) }
            else if !(error is CancellationError) {
                message = userFacingError(error)
                if (error as? APIResponseError)?.problem?.code == "invalid_cursor" {
                    nextCursor = nil
                    message = "列表分页已失效，请下拉刷新。"
                }
            }
        }
    }
}
