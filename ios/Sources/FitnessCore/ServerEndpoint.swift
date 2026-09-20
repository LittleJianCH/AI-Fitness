import Foundation

/// A server origin, never an API path or a URL containing credentials.
public struct ServerEndpoint: Hashable, Sendable {
    public let url: URL
    public var credentialScope: String { url.absoluteString }

    public init(_ value: String, allowLoopbackHTTP: Bool = false) throws {
        guard var parts = URLComponents(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/",
              parts.port.map({ (1...65535).contains($0) }) ?? true
        else { throw EndpointError.invalidOrigin }
        let scheme = parts.scheme?.lowercased()
        let loopback = ["localhost", "127.0.0.1", "[::1]"].contains(host.lowercased())
        guard scheme == "https" || (allowLoopbackHTTP && scheme == "http" && loopback)
        else { throw EndpointError.requiresHTTPS }
        parts.scheme = scheme
        parts.host = host.lowercased()
        parts.path = ""
        if (scheme == "https" && parts.port == 443) || (scheme == "http" && parts.port == 80) {
            parts.port = nil
        }
        guard let url = parts.url else { throw EndpointError.invalidOrigin }
        self.url = url
    }
}

public enum EndpointError: Error, Equatable, Sendable {
    case invalidOrigin, requiresHTTPS


}
