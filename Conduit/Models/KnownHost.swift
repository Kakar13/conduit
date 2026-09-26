import Foundation
import SwiftData

/// A trusted server host key (trust-on-first-use). Stored locally so a later
/// key change is detected and refused.
@Model
final class KnownHost {
    @Attribute(.unique) var id: String  // "host:port"
    var host: String
    var port: Int
    /// OpenSSH algorithm identifier, e.g. "ssh-ed25519".
    var keyType: String
    /// Full OpenSSH public key line: "type base64".
    var openSSHKey: String
    /// "SHA256:..." display fingerprint of the wire key blob.
    var fingerprint: String
    var firstSeen: Date
    var lastSeen: Date

    init(host: String, port: Int, keyType: String, openSSHKey: String, fingerprint: String) {
        self.id = "\(host):\(port)"
        self.host = host
        self.port = port
        self.keyType = keyType
        self.openSSHKey = openSSHKey
        self.fingerprint = fingerprint
        self.firstSeen = .now
        self.lastSeen = .now
    }
}

/// A first-use host key awaiting the user's trust decision.
struct HostKeyChallenge: Identifiable, Sendable {
    let id = UUID()
    let host: String
    let port: Int
    let keyType: String
    let fingerprint: String
    let openSSHKey: String
}

/// The server's host key changed since we last trusted it.
struct HostKeyAlert: Identifiable, Sendable {
    let id = UUID()
    let host: String
    let port: Int
    let expectedFingerprint: String
    let presentedFingerprint: String
}
