import Foundation

/// Parses a `conduit://connect?host=…&user=…&port=…&name=…` payload, as
/// printed by the pairing script or encoded in a pairing QR.
enum PairingPayload {
    struct Parsed: Equatable, Sendable {
        var host: String
        var user: String
        var port: Int
        var name: String
    }

    static func parse(_ code: String) -> Parsed? {
        guard let url = URL(string: code),
              url.scheme == "conduit",
              url.host() == "connect",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        func value(_ name: String) -> String? {
            components.queryItems?.first(where: { $0.name == name })?.value
        }

        guard let host = value("host"), !host.isEmpty,
              let user = value("user"), !user.isEmpty else {
            return nil
        }

        let name = value("name").flatMap { $0.isEmpty ? nil : $0 } ?? host
        return Parsed(
            host: host,
            user: user,
            port: Int(value("port") ?? "") ?? 22,
            name: name
        )
    }
}
