import ActivityKit
import Foundation

/// The contract between the app and the widget extension that renders the
/// Dynamic Island / Lock Screen live status. Compiled into both targets.
///
/// Static bits (which server) live in the attributes; everything that
/// changes over the session's life lives in `ContentState`.
struct ConduitActivityAttributes: ActivityAttributes, Sendable {
    public struct ContentState: Codable, Hashable, Sendable {
        public enum Status: String, Codable, Hashable, Sendable {
            case connecting
            case connected
            case reconnecting
            case offline
        }

        public var status: Status
        /// Reconnect attempt number (only meaningful for `.reconnecting`).
        public var attempt: Int

        public init(status: Status, attempt: Int = 0) {
            self.status = status
            self.attempt = attempt
        }
    }

    /// Display name, e.g. "prod-web-1".
    public var serverName: String
    /// Mono detail line, e.g. "ec2-user@ec2-….amazonaws.com:22".
    public var serverDetail: String

    public init(serverName: String, serverDetail: String) {
        self.serverName = serverName
        self.serverDetail = serverDetail
    }
}
