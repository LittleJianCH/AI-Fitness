import ContractClient
import FitnessCore
import Foundation
import SwiftUI


/// Resolve a resource at the view boundary, including SwiftUI locale overrides.
struct LocalizedText: View {
    let resource: LocalizedStringResource
    @Environment(\.locale) private var locale
    init(_ resource: LocalizedStringResource) { self.resource = resource }
    var body: some View {
        var localized = resource
        localized.locale = locale
        return Text(localized)
    }
}

struct IssueText: View {
    let issue: ClientIssue
    @Environment(\.locale) private var locale
    init(_ issue: ClientIssue) { self.issue = issue }
    var body: some View {
        var resource = issue.resource
        resource.locale = locale
        return VStack(alignment: .leading) {
            Text(resource)
            if case .api(_, _, let requestID?, _) = issue,
               requestID.range(of: #"^[A-Za-z0-9_-]{1,128}$"#, options: .regularExpression) != nil {
                Text("Request ID: \(requestID)").font(.footnote)
            }
        }
    }
}

extension ClientIssue {
    var resource: LocalizedStringResource {
        switch self {
        case .settingsSaving: "Settings are being saved. Try again shortly."
        case .settingsLoading: "Settings are loading. Try again shortly."
        case .settingsSignedOut: "Sign in again to save settings."
        case .abandonedLogin: "Sign-in was cancelled, but the server session could not be revoked. Revoke it later in session management."
        case .unsavedCredential: "Credentials could not be saved and the server session could not be revoked. Unlock this device, try again, and review this session in session management."
        case .invalidCredentials: "The username or password is incorrect."
        case .invalidCursor: "This list has changed. Pull down to refresh."
        case .analysisCancelled: "Analysis was cancelled. Try again."
        case .importConfirmed: "Import confirmed. Uploading again will not create duplicates."
        case .importFailed: "The server could not import this data. Existing workouts are unchanged."
        case .importSuppressed: "This source was deleted and blocked from reimporting."
        case .importPending: "The server has not confirmed completion. Check again later."
        case .network: "Cannot connect to the server. Check your network and try again."
        case .unknown: "The request could not be completed. Try again."
        case .cancelled: "The operation was cancelled."
        case .vault: "Cannot access secure credential storage. Unlock this device and try again."
        case .logoutIncomplete: "Sign-out has not completed. Try again."
        case .endpoint(.invalidOrigin): "Enter a server address with its protocol and optional port, without a path, query, or account information."
        case .endpoint(.requiresHTTPS): "The server requires HTTPS. Development builds allow HTTP only for loopback addresses."
        case .healthExport(.invalidData): "This data cannot be safely exported."
        case .healthExport(.busy): "This workout is being exported. Try again shortly."
        case .healthExport(.uncertainWorkout): "The Apple Health write has not been confirmed. Unlock this device and allow read access, then retry. The workout will not be written again."
        case .healthExport(.uncertainRoute): "The workout was written, but the route has not been confirmed. Unlock this device and allow read access, then retry."
        case .healthExport(.invalidReceipt): "Apple Health was updated, but the server receipt was not confirmed. Try again."
        case .healthExport(.storage): "Cannot access export recovery records. Unlock this device and check available storage."
        case .healthImport(.unavailable): "Apple Health is unavailable on this device."
        case .healthImport(.unsupportedWorkout): "Only single-sport cycling and running workouts are supported. Multisport workouts are not supported yet."
        case .healthImport(.ambiguousSamples): "This workout contains overlapping or unsupported samples and cannot be fully imported yet."
        case .healthImport(.tooManySamples): "This workout has too many samples to import."
        case .healthImport(.missingWorkout): "This Apple Health workout cannot be read. Select it again."
        case .healthImport(.invalidAcknowledgement): "The server did not return a complete import result. Check again."
        case .api(let status, let code, _, _):
            switch code {
            case "analysis_too_large": "This history exceeds the processing limit. Choose a shorter date range and try again."
            case "analysis_unavailable": "This history cannot be calculated. Adjust the analysis options and try again."
            case "invalid_credentials": "The username or password is incorrect."
            default:
                switch status {
                case 401: "Your session has expired. Sign in again."
                case 403: "This action is not allowed."
                case 404: "This record does not exist or was deleted."
                case 409: "The data has changed. Refresh and try again."
                case 413: "This data exceeds the server limit and cannot be submitted."
                case 422: "The submitted data is invalid. Check it and try again."
                case 429: "Too many requests. Try again later."
                default: "The server could not complete the request. Try again."
                }
            }
        }
    }
}

extension Workout {
    var sportName: String { String(localized: sportKind == .running ? "Running" : "Cycling") }
    var displayTitle: String { workoutUserData.workoutTitle ?? sportName }
}
extension WorkoutCard {
    var displayTitle: String { userData.workoutTitle ?? summary.sportName }
}
extension Components.Schemas.SportSummary {
    var sportName: String { String(localized: sportKind == .running ? "Running" : "Cycling") }
}
extension WorkoutMetric {
    var localizedTitle: String { String(localized: titleResource) }
    var titleResource: LocalizedStringResource {
        switch title {
        case .heartRate: "Heart rate"
        case .power: "Power"
        case .speed: "Speed"
        case .grade: "Grade"
        case .temperature: "Ambient temperature"
        case .altitude: "Altitude"
        case .cyclingCadence: "Cycling cadence"
        case .runningCadence: "Running cadence"
        case .stepLength: "Step length"
        case .verticalOscillation: "Vertical oscillation"
        case .groundContactTime: "Ground contact time"
        }
    }
    func localizedValue(_ canonical: Double?) -> String {
        WorkoutFormat.number(canonical.map { $0 * canonicalScale }, unit: unit, fractionDigits: fractionDigits)
    }
}

enum WorkoutFormat {
    static func number(_ value: Double?, unit: String, fractionDigits: Int = 0) -> String {
        FitnessCore.WorkoutFormat.number(value, unit: unit, fractionDigits: fractionDigits, missing: String(localized: "No data"))
    }
    static func distance(_ value: Double?) -> String { FitnessCore.WorkoutFormat.distance(value, missing: String(localized: "No data")) }
    static func duration(_ value: Double?) -> String { FitnessCore.WorkoutFormat.duration(value, missing: String(localized: "No data")) }
    static func pace(_ value: Double?) -> String { FitnessCore.WorkoutFormat.pace(value, missing: String(localized: "No data")) }
}

extension HealthExportPlan {
    static var projectionNotice: LocalizedStringResource {
        "Exports cycling or running, supported recorded samples such as heart rate, power and speed, and route coordinates. Distance and energy use recorded totals without adding cumulative streams again; missing totals are not inferred. Apple Health calculates duration from start, end and pause events, which can differ from the recorded summary. Route accuracy is unknown and is not fabricated; altitude is omitted. Laps, running cadence, notes, tags, calculated summaries and other unsupported fields are omitted. This is a platform copy, not a complete backup. A new revision creates a new copy."
    }
}
