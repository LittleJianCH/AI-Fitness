import ContractClient
import Foundation
import HTTPTypes
import OpenAPIRuntime
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
