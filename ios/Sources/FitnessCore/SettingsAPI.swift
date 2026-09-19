import ContractClient

public typealias UserSettings = Components.Schemas.UserSettings
public typealias BodyProfile = Components.Schemas.BodyProfile
public typealias SportProfile = Components.Schemas.SportProfile
public typealias HeartRateProfile = Components.Schemas.HeartRateProfile
public typealias Equipment = Components.Schemas.Equipment

public protocol SettingsService: Sendable {
    func settings(token: String) async throws -> UserSettings
    func saveSettings(token: String, settings: UserSettings) async throws -> UserSettings
}

extension FitnessAPI: SettingsService {
    public func settings(token: String) async throws -> UserSettings {
        try await apiCall { try await client(token: token).get_settings().ok.body.application_json_charset_utf_hyphen_8 }
    }

    public func saveSettings(token: String, settings: UserSettings) async throws -> UserSettings {
        try await apiCall {
            try await client(token: token).put_settings(body: .application_json_charset_utf_hyphen_8(settings))
                .ok.body.application_json_charset_utf_hyphen_8
        }
    }
}
