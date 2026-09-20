import ContractClient
import Foundation
import Observation

public typealias TrainingHistory = Components.Schemas.TrainingHistory
public typealias TrainingHistoryRequest = Components.Schemas.TrainingHistoryRequest

public protocol TrainingHistoryService: Sendable {
    func trainingHistory(token: String, request: TrainingHistoryRequest) async throws -> TrainingHistory
}

extension FitnessAPI: TrainingHistoryService {
    public func trainingHistory(token: String, request: TrainingHistoryRequest) async throws -> TrainingHistory {
        try await apiCall {
            try await client(token: token).post_analysis_training_history(body: .application_json_charset_utf_hyphen_8(request))
                .ok.body.application_json_charset_utf_hyphen_8
        }
    }
}

public enum TrainingCalendar {
    /// Foundation supplies actual local-day boundaries, including daylight-saving
    /// changes. The backend validates them and owns all load calculations.
    public static func days(ending: Date, count: Int, timeZone: TimeZone, complete: Bool) -> [Components.Schemas.CalendarDay] {
        guard (1...366).contains(count) else { return [] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let end = calendar.startOfDay(for: ending)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return (0..<count).compactMap { index in
            // Midnight can normalize to 01:00. Resolve each civil day's interval
            // independently so that hour cannot carry into another boundary.
            guard let candidate = calendar.date(byAdding: .day, value: index-count+1, to: end),
                  let day = calendar.dateInterval(of: .day, for: candidate) else { return nil }
            return .init(calendarDate: formatter.string(from: day.start), calendarEnd: day.end,
                         calendarRecordingComplete: complete, calendarStart: day.start)
        }
    }
}

@MainActor @Observable
public final class TrainingHistoryStore {
    public private(set) var history: TrainingHistory?
    public private(set) var isLoading = false
    public private(set) var message: ClientIssue?
    @ObservationIgnored private let service: any TrainingHistoryService
    @ObservationIgnored private let session: SessionStore
    @ObservationIgnored private var generation: UInt64 = 0

    public init(service: any TrainingHistoryService, session: SessionStore) {
        self.service = service
        self.session = session
    }

    public func load(_ input: TrainingHistoryRequest) async {
        generation &+= 1
        let request = generation
        let identity = session.generation
        history = nil
        message = nil
        guard let token = session.token, session.user != nil else { isLoading = false; return }
        isLoading = true
        defer { if generation == request { isLoading = false } }
        do {
            let result = try await service.trainingHistory(token: token, request: input)
            guard request == generation, identity == session.generation else { return }
            try Task.checkCancellation()
            history = result
        } catch {
            guard request == generation, identity == session.generation else { return }
            if (error as? APIResponseError)?.status == 401 { session.handleUnauthorized(for: identity) }
            else if !Task.isCancelled && !(error is CancellationError) { message = ClientIssue(error) }
        }
    }
}
