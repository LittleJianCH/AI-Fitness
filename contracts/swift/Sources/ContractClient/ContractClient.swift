import Foundation
import OpenAPIRuntime

/// Creates the generated client with the AI Fitness wire configuration.
public func makeFitnessClient(
    serverURL: URL,
    transport: any ClientTransport,
    middlewares: [any ClientMiddleware] = []
) -> Client {
    Client(
        serverURL: serverURL,
        configuration: Configuration(dateTranscoder: FitnessDateTranscoder()),
        transport: transport,
        middlewares: middlewares
    )
}
