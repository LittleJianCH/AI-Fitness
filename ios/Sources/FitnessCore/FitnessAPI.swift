import ContractClient
import Foundation
import HTTPTypes
import OpenAPIRuntime
import OpenAPIURLSession

public typealias FitnessUser = Components.Schemas.User

public protocol AuthService: Sendable {
    func login(username: String, password: String, deviceName: String) async throws -> Components.Schemas.NativeSession
    func currentUser(token: String) async throws -> FitnessUser
    func logout(token: String) async throws
}

public struct FitnessAPI: AuthService, Sendable {
    public let endpoint: ServerEndpoint
    let transport: any ClientTransport

    public init(endpoint: ServerEndpoint, transport: any ClientTransport) {
        self.endpoint = endpoint
        self.transport = transport
    }

    public init(endpoint: ServerEndpoint) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 120
        let session = URLSession(configuration: configuration, delegate: RefuseRedirects(), delegateQueue: nil)
        self.init(endpoint: endpoint, transport: URLSessionTransport(configuration: .init(session: session)))
    }

    func client(token: String? = nil) -> Client {
        makeFitnessClient(serverURL: endpoint.url, transport: transport, middlewares: [RequestBoundary(token: token)])
    }

    public func login(username: String, password: String, deviceName: String) async throws -> Components.Schemas.NativeSession {
        try await apiCall {
            try await client().post_auth_native_login(body: .application_json_charset_utf_hyphen_8(
                .init(deviceName: deviceName, password: password, username: username)
            )).ok.body.application_json_charset_utf_hyphen_8
        }
    }

    public func currentUser(token: String) async throws -> FitnessUser {
        try await apiCall { try await client(token: token).get_me().ok.body.application_json_charset_utf_hyphen_8 }
    }

    public func logout(token: String) async throws {
        try await apiCall { _ = try await client(token: token).post_auth_logout().noContent }
    }
}

/// Keep generated-client diagnostics (which may contain a request body) out of UI/logs.
func apiCall<T>(_ operation: () async throws -> T) async throws -> T {
    do { return try await operation() }
    catch let error as ClientError { throw error.underlyingError }
}

public struct APIResponseError: Error, Sendable {
    public let status: Int
    public let problem: Components.Schemas.Problem?
    public let retryAfter: String?
}

public func userFacingError(_ error: any Error) -> String {
    if let response = error as? APIResponseError {
        switch response.status {
        case 401: return "登录已失效，请重新登录。"
        case 403: return "当前操作未获允许。"
        case 404: return "记录不存在或已被删除。"
        case 409: return "数据已经变化，请刷新后重试。"
        case 413: return "数据量超过服务器限制，暂时无法提交。"
        case 422: return "提交的数据不符合要求，请检查后重试。"
        case 429: return "请求过于频繁，请稍后重试。"
        default: return "服务器暂时无法完成请求，请重试。"
        }
    }
    return "暂时无法连接服务器，请检查网络后重试。"
}

struct RequestBoundary: ClientMiddleware {
    let token: String?

    func intercept(
        _ request: HTTPRequest, body: HTTPBody?, baseURL: URL, operationID: String,
        next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var request = request
        if let token { request.headerFields[.authorization] = "Bearer \(token)" }
        let (response, responseBody) = try await next(request, body, baseURL)
        guard (200..<300).contains(response.status.code) else {
            var problem: Components.Schemas.Problem?
            if let responseBody {
                // Error bodies are bounded; raw HTML/proxy diagnostics are never shown.
                do {
                    let data = try await Data(collecting: responseBody, upTo: 65_536)
                    problem = try JSONDecoder().decode(Components.Schemas.Problem.self, from: data)
                } catch is CancellationError { throw CancellationError() }
                catch { /* HTTP status remains actionable if an intermediary returned another shape. */ }
            }
            throw APIResponseError(status: response.status.code, problem: problem, retryAfter: response.headerFields[.retryAfter])
        }
        return (response, responseBody)
    }
}

private final class RefuseRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) { completionHandler(nil) }
}
