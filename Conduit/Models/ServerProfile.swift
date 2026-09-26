import Foundation
import SwiftData

/// A saved remote server (e.g. an EC2 instance).
@Model
final class ServerProfile {
    @Attribute(.unique) var id: UUID
    var name: String
    var host: String
    var port: Int
    var username: String

    /// Optional command injected right after the shell opens — typically a
    /// terminal multiplexer attach such as `tmux new -A -s conduit`, which
    /// makes reconnects after a network handoff land back in the same
    /// remote session.
    var reattachCommand: String

    var lastConnectedAt: Date?

    init(
        name: String,
        host: String,
        port: Int = 22,
        username: String,
        reattachCommand: String = ""
    ) {
        self.id = UUID()
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.reattachCommand = reattachCommand
    }
}
