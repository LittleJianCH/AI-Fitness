import Foundation

public indirect enum ClientIssue: Equatable, Sendable {
    case api(status: Int, code: String?, requestID: String?, retryAfter: String?)
    case network, unknown, cancelled, vault
    case endpoint(EndpointError), healthImport(HealthImportError), healthExport(HealthExportError)
    case settingsSaving, settingsLoading, settingsSignedOut
    case abandonedLogin, unsavedCredential, invalidCredentials, logoutIncomplete(ClientIssue)
    case invalidCursor, analysisCancelled
    case importConfirmed, importFailed, importSuppressed, importPending

    public init(_ error: any Error) {
        if let response = error as? APIResponseError {
            self = .api(status: response.status, code: response.problem?.code,
                        requestID: response.problem?.requestId, retryAfter: response.retryAfter)
        } else if let error = error as? EndpointError { self = .endpoint(error)
        } else if let error = error as? HealthImportError { self = .healthImport(error)
        } else if let error = error as? HealthExportError { self = .healthExport(error)
        } else if error is VaultError { self = .vault
        } else if error is CancellationError { self = .cancelled
        } else if let error = error as? URLError { self = error.code == .cancelled ? .cancelled : .network
        } else { self = .unknown }
    }
}
