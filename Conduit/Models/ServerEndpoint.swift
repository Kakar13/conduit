import Foundation

/// A Sendable snapshot of a `ServerProfile`, safe to hand across actor
/// boundaries into the SSH engine.
struct ServerEndpoint: Equatable, Sendable {
    var host: String
    var port: Int
    var username: String
    var reattachCommand: String
}

extension ServerProfile {
    /// Copies the persisted profile into a Sendable value the SSH actor can
    /// own.
    var endpoint: ServerEndpoint {
        ServerEndpoint(
            host: host,
            port: port,
            username: username,
            reattachCommand: reattachCommand
        )
    }
}
