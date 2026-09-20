import Foundation
import Observation

public enum SessionPhase: Equatable {
    case signedOut, restoring, signingIn, signedIn(FitnessUser), restoreFailed, signingOut(FitnessUser)
}

/// One app-owned identity. A generation prevents responses for old sessions from publishing UI state.
@MainActor @Observable
public final class SessionStore {
    public private(set) var phase: SessionPhase = .signedOut
    public private(set) var message: ClientIssue?
    public private(set) var generation: UInt64 = 0
    public private(set) var token: String?
    @ObservationIgnored private let service: any AuthService
    @ObservationIgnored private let vault: any CredentialVault

    public init(service: any AuthService, vault: any CredentialVault) {
        self.service = service
        self.vault = vault
    }

    public var user: FitnessUser? {
        switch phase {
        case .signedIn(let user), .signingOut(let user): user
        default: nil
        }
    }

    public func restore() async {
        guard phase == .signedOut || phase == .restoreFailed else { return }
        generation &+= 1
        let operation = generation
        phase = .restoring
        message = nil
        do {
            guard let stored = try vault.read() else { phase = .signedOut; return }
            let user = try await service.currentUser(token: stored)
            guard operation == generation else { return }
            try Task.checkCancellation()
            token = stored
            phase = .signedIn(user)
        } catch {
            guard operation == generation else { return }
            if (error as? APIResponseError)?.status == 401 {
                clearCredential()
            } else {
                phase = .restoreFailed
                message = ClientIssue(error)
            }
        }
    }

    public func login(username: String, password: String, deviceName: String) async {
        guard phase == .signedOut else { return }
        generation &+= 1
        let operation = generation
        phase = .signingIn
        message = nil
        do {
            let result = try await service.login(username: username, password: password, deviceName: deviceName)
            guard operation == generation, !Task.isCancelled else {
                // A discarded login response still created a server session.
                let revoked = await revokeAbandonedLogin(result.token)
                if operation == generation {
                    phase = .signedOut
                    if !revoked { message = .abandonedLogin }
                }
                return
            }
            do { try vault.write(result.token) }
            catch {
                let revoked = await revokeAbandonedLogin(result.token)
                if !revoked, operation == generation {
                    phase = .signedOut
                    message = .unsavedCredential
                    return
                }
                throw error
            }
            token = result.token
            phase = .signedIn(result.user)
        } catch {
            guard operation == generation else { return }
            phase = .signedOut
            if error is CancellationError { return }
            message = (error as? APIResponseError)?.status == 401
                ? .invalidCredentials
                : (ClientIssue(error))
        }
    }

    public func logout() async {
        guard case .signedIn(let user) = phase, let token else { return }
        generation &+= 1
        let operation = generation
        phase = .signingOut(user)
        message = nil
        do {
            try await service.logout(token: token)
            guard operation == generation else { return }
            clearCredential()
        } catch {
            guard operation == generation else { return }
            if (error as? APIResponseError)?.status == 401 { clearCredential() }
            else {
                phase = .signedIn(user)
                message = .logoutIncomplete(ClientIssue(error))
            }
        }
    }

    public func handleUnauthorized(for expectedGeneration: UInt64) {
        guard generation == expectedGeneration else { return }
        generation &+= 1
        clearCredential()
    }

    /// Explicitly abandon an unavailable saved session, without claiming remote revocation.
    public func forgetSavedSession() {
        generation &+= 1
        clearCredential()
    }

    private func clearCredential() {
        token = nil
        do {
            try vault.remove()
            phase = .signedOut
            message = nil
        } catch {
            phase = .restoreFailed
            message = ClientIssue(error)
        }
    }

    private func revokeAbandonedLogin(_ credential: String) async -> Bool {
        // Revocation must reach the server even if its caller was cancelled.
        // This unstructured task is deliberately cancellation-independent and
        // remains owned/awaited here; the transport bounds its network lifetime.
        let cleanup = Task { [service] in
            do { try await service.logout(token: credential); return true }
            catch { return (error as? APIResponseError)?.status == 401 }
        }
        return await cleanup.value
    }
}
