import ContractClient
import XCTest
@testable import FitnessCore

final class SessionTests: XCTestCase {
    @MainActor
    func testLoginPersistsCredentialAndRestoreUsesServerIdentity() async {
        let service = TestAuth()
        let vault = MemoryVault()
        let store = SessionStore(service: service, vault: vault)
        await store.login(username: "alice", password: "synthetic password", deviceName: "Test")
        XCTAssertEqual(vault.token, "synthetic-token")
        XCTAssertEqual(store.user?.username, "alice")
        let restored = SessionStore(service: service, vault: vault)
        await restored.restore()
        XCTAssertEqual(restored.user, store.user)
    }

    @MainActor
    func testNetworkFailurePreservesCredentialButUnauthorizedRemovesIt() async {
        let service = TestAuth()
        let vault = MemoryVault(token: "synthetic-token")
        let store = SessionStore(service: service, vault: vault)
        await service.setFailure(.offline)
        await store.restore()
        XCTAssertEqual(store.phase, .restoreFailed)
        XCTAssertNotNil(vault.token)
        await service.setFailure(.unauthorized)
        await store.restore()
        XCTAssertEqual(store.phase, .signedOut)
        XCTAssertNil(vault.token)
    }

    @MainActor
    func testFailedLogoutDoesNotClaimRemoteRevocation() async {
        let service = TestAuth()
        let vault = MemoryVault()
        let store = SessionStore(service: service, vault: vault)
        await store.login(username: "alice", password: "synthetic", deviceName: "Test")
        await service.setFailure(.offline)
        await store.logout()
        XCTAssertNotNil(store.user)
        XCTAssertNotNil(vault.token)
        XCTAssertNotNil(store.message)
        await service.setFailure(nil)
        await store.logout()
        XCTAssertEqual(store.phase, .signedOut)
        XCTAssertNil(vault.token)
    }

    @MainActor
    func testOldUnauthorizedResponseCannotClearNewLogin() async {
        let service = TestAuth()
        let vault = MemoryVault()
        let store = SessionStore(service: service, vault: vault)
        await store.login(username: "alice", password: "synthetic", deviceName: "Test")
        let oldGeneration = store.generation
        await store.logout()
        await store.login(username: "alice", password: "synthetic", deviceName: "Test")
        store.handleUnauthorized(for: oldGeneration)
        XCTAssertNotNil(store.user)
        XCTAssertNotNil(vault.token)
    }

    @MainActor
    func testLateRestoreCannotResurrectForgottenSession() async {
        let service = TestAuth()
        await service.pauseRestore()
        let vault = MemoryVault(token: "synthetic-token")
        let store = SessionStore(service: service, vault: vault)
        let task = Task { await store.restore() }
        await service.waitForRestore()
        store.forgetSavedSession()
        await service.resumeRestore()
        await task.value
        XCTAssertEqual(store.phase, .signedOut)
        XCTAssertNil(store.token)
        XCTAssertNil(vault.token)
    }

    @MainActor
    func testWrongPasswordIsNotPresentedAsExpiredSession() async {
        let service = TestAuth()
        await service.setFailure(.unauthorized)
        let store = SessionStore(service: service, vault: MemoryVault())
        await store.login(username: "alice", password: "wrong", deviceName: "Test")
        XCTAssertEqual(store.phase, .signedOut)
        XCTAssertEqual(store.message, "用户名或密码不正确。")
    }
}

@MainActor
final class MemoryVault: CredentialVault {
    var token: String?
    init(token: String? = nil) { self.token = token }
    func read() throws -> String? { token }
    func write(_ token: String) throws { self.token = token }
    func remove() throws { token = nil }
}

actor TestAuth: AuthService {
    enum Failure { case offline, unauthorized }
    var failure: Failure?
    var paused = false
    var restoreContinuation: CheckedContinuation<Void, Never>?
    var observer: CheckedContinuation<Void, Never>?
    let user = FitnessUser(createdAt: Date(timeIntervalSince1970: 0), id: "00000000-0000-0000-0000-000000000001", username: "alice")

    func setFailure(_ value: Failure?) { failure = value }
    func pauseRestore() { paused = true }
    func waitForRestore() async {
        if restoreContinuation != nil { return }
        await withCheckedContinuation { observer = $0 }
    }
    func resumeRestore() { restoreContinuation?.resume(); restoreContinuation = nil }

    func check() throws {
        switch failure {
        case .offline: throw URLError(.notConnectedToInternet)
        case .unauthorized: throw APIResponseError(status: 401, problem: nil, retryAfter: nil)
        case nil: break
        }
    }
    func login(username: String, password: String, deviceName: String) async throws -> Components.Schemas.NativeSession {
        try check()
        let now = Date(timeIntervalSince1970: 0)
        return .init(session: .init(absoluteExpiresAt: now, createdAt: now, current: true, id: "session", idleExpiresAt: now, lastSeenAt: now, transport: .native), token: "synthetic-token", user: user)
    }
    func currentUser(token: String) async throws -> FitnessUser {
        if paused {
            await withCheckedContinuation { continuation in
                restoreContinuation = continuation
                observer?.resume()
                observer = nil
            }
        }
        try check()
        return user
    }
    func logout(token: String) async throws { try check() }
}
