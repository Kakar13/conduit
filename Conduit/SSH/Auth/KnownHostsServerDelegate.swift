import Foundation
import NIOCore
import NIOSSH

/// Validates the server's host key during the SSH handshake by deferring to
/// the trust-on-first-use store. The decision is async (it may need a user
/// prompt), which the promise-based delegate API supports directly.
final class KnownHostsServerDelegate: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
    private let verify: @Sendable (NIOSSHPublicKey) async -> Bool

    init(verify: @escaping @Sendable (NIOSSHPublicKey) async -> Bool) {
        self.verify = verify
    }

    func validateHostKey(
        hostKey: NIOSSHPublicKey,
        validationCompletePromise: EventLoopPromise<Void>
    ) {
        Task {
            if await verify(hostKey) {
                validationCompletePromise.succeed(())
            } else {
                validationCompletePromise.fail(SSHSessionError.hostKeyRejected)
            }
        }
    }
}
