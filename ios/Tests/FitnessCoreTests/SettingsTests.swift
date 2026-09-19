import ContractClient
import Foundation
import HTTPTypes
import OpenAPIRuntime
import Observation
import XCTest
@testable import FitnessCore

final class SettingsTests: XCTestCase {
    func testGeneratedSettingsRequestPreservesRevisionAndBody() async throws {
        let bytes = Data(#"{"settingsRevision":"9007199254740993","settingsSoftware":{"softwareAppearance":"systemAppearance"},"settingsBodyProfiles":[],"settingsEquipment":[]}"#.utf8)
        let api = FitnessAPI(endpoint: try ServerEndpoint("https://fitness.invalid"), transport: FixtureTransport { request, body, _ in
            XCTAssertEqual(request.path, "/api/v1/settings")
            XCTAssertEqual(request.headerFields[.authorization], "Bearer synthetic")
            if request.method == .put {
                let sent = try await Data(collecting: XCTUnwrap(body), upTo: 65536)
                let object = try XCTUnwrap(JSONSerialization.jsonObject(with: sent) as? [String: Any])
                XCTAssertEqual(object["settingsRevision"] as? String, "9007199254740993")
                XCTAssertNotNil(object["settingsBodyProfiles"])
            }
            return (HTTPResponse(status: .ok, headerFields: [.contentType: "application/json; charset=utf-8"]), HTTPBody(bytes))
        })
        let settings = try await api.settings(token: "synthetic")
        XCTAssertEqual(settings.settingsRevision, "9007199254740993")
        let saved = try await api.saveSettings(token: "synthetic", settings: settings)
        XCTAssertEqual(settings, saved)
    }

    @MainActor func testCancelledAndOldSessionLoadsCannotPublishSettings() async {
        let service = ControlledSettings()
        let session = await signedIn()
        let store = SettingsStore(service: service, session: session)
        let cancelled = Task { await store.load() }
        await service.waitForRequest()
        cancelled.cancel()
        await service.respond(.success(empty))
        await cancelled.value
        XCTAssertNil(store.settings)
        XCTAssertNil(store.message)
        let stale = Task { await store.load() }
        await service.waitForRequest()
        session.forgetSavedSession()
        await service.respond(.success(empty))
        await stale.value
        XCTAssertNil(store.settings)
        XCTAssertFalse(store.isLoading)
    }

    @MainActor func testConflictingSaveKeepsPreviousDataAndDoesNotClaimSuccess() async {
        let service = ControlledSettings()
        let store = SettingsStore(service: service, session: await signedIn())
        let load = Task { await store.load() }
        await service.waitForRequest()
        await service.respond(.success(empty))
        await load.value
        var proposed = empty
        proposed.settingsSoftware.softwareAppearance = .darkAppearance
        let save = Task { await store.save(proposed) }
        await service.waitForRequest()
        await service.respond(.failure(APIResponseError(status: 409, problem: nil, retryAfter: nil)))
        let didSave = await save.value
        XCTAssertFalse(didSave)
        XCTAssertEqual(store.settings, empty)
        XCTAssertNotNil(store.message)
        XCTAssertFalse(store.isSaving)
    }

    @MainActor func testOldUnauthorizedSaveCannotRevokeAnotherSession() async {
        let service = ControlledSettings()
        let session = await signedIn()
        let store = SettingsStore(service: service, session: session)
        let save = Task { await store.save(empty) }
        await service.waitForRequest()
        session.forgetSavedSession()
        await session.login(username: "alice", password: "synthetic", deviceName: "Test")
        await service.respond(.failure(APIResponseError(status: 401, problem: nil, retryAfter: nil)))
        let didSave = await save.value
        XCTAssertFalse(didSave)
        XCTAssertNotNil(session.user)
        XCTAssertNil(store.message)
    }

    @MainActor func testSettingsObservationResumesAfterAccountChangeBeforeLoad() async {
        let session = SessionStore(service: SettingsAccounts(), vault: MemoryVault())
        let service = DelayedAccountSettings(alice: empty, bob: empty)
        await session.login(username: "alice", password: "synthetic", deviceName: "Test")
        let store = SettingsStore(service: service, session: session)
        await store.load()
        await session.logout()
        await session.login(username: "bob", password: "synthetic", deviceName: "Test")
        let changed = expectation(description: "A settings reader observes the new session's load")
        withObservationTracking {
            XCTAssertNil(store.settings)
        } onChange: {
            changed.fulfill()
        }
        await store.load()
        await fulfillment(of: [changed], timeout: 1)
        XCTAssertEqual(store.settings, empty)
    }

    @MainActor func testAccountChangeClearsSettingsDuringDelayedSave() async {
        for loadWhileSignedOut in [false, true] {
            for unauthorized in [false, true] {
                var alice = empty
                alice.settingsEquipment = [.init(equipmentId: "alice-bike", equipmentKind: .bicycle, equipmentName: "Alice private bicycle", equipmentRetired: false)]
                var bob = empty
                bob.settingsRevision = "8"
                let service = DelayedAccountSettings(alice: alice, bob: bob)
                let session = SessionStore(service: SettingsAccounts(), vault: MemoryVault())
                await session.login(username: "alice", password: "synthetic", deviceName: "Test")
                let store = SettingsStore(service: service, session: session)
                await store.load()
                XCTAssertEqual(store.settings, alice)
                let oldSave = Task { await store.save(alice) }
                await service.waitForSave(token: "alice")
                XCTAssertTrue(store.isSaving)
                // A same-session refresh must still preserve the active save.
                await store.load()
                XCTAssertEqual(store.settings, alice)
                XCTAssertTrue(store.isSaving)
                await session.logout()
                XCTAssertNil(store.settings)
                if loadWhileSignedOut {
                    await store.load()
                    XCTAssertNil(store.settings)
                    XCTAssertNil(store.message)
                    XCTAssertFalse(store.isSaving)
                    XCTAssertFalse(store.isLoading)
                }
                await session.login(username: "bob", password: "synthetic", deviceName: "Test")
                XCTAssertNil(store.settings)
                await store.load()
                XCTAssertEqual(store.settings, bob)
                XCTAssertFalse(store.isSaving)
                XCTAssertFalse(store.isLoading)
                var proposed = bob
                proposed.settingsSoftware.softwareAppearance = .darkAppearance
                let newSave = Task { await store.save(proposed) }
                await service.waitForSave(token: "bob")
                let result: Result<UserSettings, Error> = unauthorized
                    ? .failure(APIResponseError(status: 401, problem: nil, retryAfter: nil)) : .success(alice)
                await service.respond(token: "alice", result: result)
                let saved = await oldSave.value
                XCTAssertFalse(saved)
                XCTAssertEqual(store.settings, bob)
                XCTAssertEqual(session.user?.username, "bob")
                XCTAssertNil(store.message)
                XCTAssertTrue(store.isSaving)
                await service.respond(token: "bob", result: .success(proposed))
                let newSaved = await newSave.value
                XCTAssertTrue(newSaved)
                XCTAssertEqual(store.settings, proposed)
                XCTAssertFalse(store.isSaving)
            }
        }
    }

    private var empty: UserSettings {
        .init(settingsBodyProfiles: [], settingsEquipment: [], settingsRevision: "0", settingsSoftware: .init(softwareAppearance: .systemAppearance))
    }

    @MainActor private func signedIn() async -> SessionStore {
        let session = SessionStore(service: TestAuth(), vault: MemoryVault())
        await session.login(username: "alice", password: "synthetic", deviceName: "Test")
        return session
    }
}

private actor ControlledSettings: SettingsService {
    private var pending: CheckedContinuation<UserSettings, Error>?
    private var observer: CheckedContinuation<Void, Never>?
    func settings(token: String) async throws -> UserSettings { try await response() }
    func saveSettings(token: String, settings: UserSettings) async throws -> UserSettings { try await response() }
    private func response() async throws -> UserSettings {
        try await withCheckedThrowingContinuation { continuation in
            pending = continuation
            observer?.resume()
            observer = nil
        }
    }
    func waitForRequest() async {
        if pending != nil { return }
        await withCheckedContinuation { observer = $0 }
    }
    func respond(_ result: Result<UserSettings, Error>) {
        let continuation = pending
        pending = nil
        continuation?.resume(with: result)
    }
}

private struct SettingsAccounts: AuthService {
    func login(username: String, password: String, deviceName: String) async throws -> Components.Schemas.NativeSession {
        let now = Date(timeIntervalSince1970: 0)
        return .init(session: .init(absoluteExpiresAt: now, createdAt: now, current: true, id: username,
                                   idleExpiresAt: now, lastSeenAt: now, transport: .native),
                     token: username, user: try await currentUser(token: username))
    }
    func currentUser(token: String) async throws -> FitnessUser {
        .init(createdAt: Date(timeIntervalSince1970: 0), id: token, username: token)
    }
    func logout(token: String) async throws {}
}

private actor DelayedAccountSettings: SettingsService {
    let alice: UserSettings
    let bob: UserSettings
    private var pending: [String: CheckedContinuation<UserSettings, Error>] = [:]
    private var observers: [String: CheckedContinuation<Void, Never>] = [:]
    init(alice: UserSettings, bob: UserSettings) { self.alice = alice; self.bob = bob }
    func settings(token: String) async throws -> UserSettings { token == "alice" ? alice : bob }
    func saveSettings(token: String, settings: UserSettings) async throws -> UserSettings {
        try await withCheckedThrowingContinuation { continuation in
            pending[token] = continuation
            observers.removeValue(forKey: token)?.resume()
        }
    }
    func waitForSave(token: String) async {
        if pending[token] != nil { return }
        await withCheckedContinuation { observers[token] = $0 }
    }
    func respond(token: String, result: Result<UserSettings, Error>) {
        pending.removeValue(forKey: token)?.resume(with: result)
    }
}
