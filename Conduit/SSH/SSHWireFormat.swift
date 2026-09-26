import CryptoKit
import Foundation

/// Minimal SSH wire-format helpers used for public key export and
/// fingerprints.
enum SSHWireFormat {
    /// Encodes an SSH `string`: uint32 length prefix + bytes.
    static func string(_ bytes: some Collection<UInt8>) -> Data {
        var data = Data()
        var length = UInt32(bytes.count).bigEndian
        data.append(Data(bytes: &length, count: 4))
        data.append(contentsOf: bytes)
        return data
    }

    /// Builds the OpenSSH public key line for a P-256 key:
    /// `ecdsa-sha2-nistp256 base64(string "ecdsa-sha2-nistp256" |
    /// string "nistp256" | string Q)` where Q is the x9.63 point.
    static func openSSHECDSAP256PublicKey(x963Representation: Data, comment: String) -> String {
        var blob = Data()
        blob.append(string("ecdsa-sha2-nistp256".utf8))
        blob.append(string("nistp256".utf8))
        blob.append(string(x963Representation))
        return "ecdsa-sha2-nistp256 \(blob.base64EncodedString()) \(comment)"
    }

    /// The OpenSSH-style display fingerprint: SHA-256 over the wire blob,
    /// base64 without padding, e.g. `SHA256:abc123…`.
    static func fingerprint(openSSHKey: String) -> String {
        let parts = openSSHKey.split(separator: " ")
        guard parts.count >= 2, let blob = Data(base64Encoded: String(parts[1])) else {
            return "SHA256:unknown"
        }
        let digest = SHA256.hash(data: blob)
        let base64 = Data(digest).base64EncodedString()
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
        return "SHA256:\(base64)"
    }
}
