import Foundation
import SwiftData

/// Trust-on-first-use store for server host keys, backed by SwiftData.
@MainActor
final class KnownHostStore {
    /// Only Sendable values cross back to the SSH actor — never models.
    enum LookupResult: Sendable {
        case match
        case mismatch(expectedFingerprint: String)
        case unknown
    }

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func lookup(host: String, port: Int, presentedKey: String) -> LookupResult {
        let id = "\(host):\(port)"
        var descriptor = FetchDescriptor<KnownHost>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let known = try? modelContext.fetch(descriptor).first else {
            return .unknown
        }
        if known.openSSHKey == presentedKey {
            known.lastSeen = .now
            try? modelContext.save()
            return .match
        }
        return .mismatch(expectedFingerprint: known.fingerprint)
    }

    func store(host: String, port: Int, keyType: String, openSSHKey: String, fingerprint: String) {
        let known = KnownHost(
            host: host,
            port: port,
            keyType: keyType,
            openSSHKey: openSSHKey,
            fingerprint: fingerprint
        )
        modelContext.insert(known)
        try? modelContext.save()
    }

    func remove(host: String, port: Int) {
        let id = "\(host):\(port)"
        var descriptor = FetchDescriptor<KnownHost>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        if let known = try? modelContext.fetch(descriptor).first {
            modelContext.delete(known)
            try? modelContext.save()
        }
    }
}
