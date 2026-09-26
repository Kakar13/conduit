import Foundation
import NIOConcurrencyHelpers
import NIOCore
import NIOSSH

/// Offers the Secure Enclave private key for public-key authentication. The
/// key never leaves the enclave: swift-nio-ssh hands the challenge to
/// CryptoKit, which asks the enclave to sign it.
final class ConduitUserAuthDelegate: NIOSSHClientUserAuthenticationDelegate, @unchecked Sendable {
    private let username: String
    private let privateKey: NIOSSHPrivateKey
    private let didOffer = NIOLockedValueBox(false)

    init(username: String, privateKey: NIOSSHPrivateKey) {
        self.username = username
        self.privateKey = privateKey
    }

    func nextAuthenticationType(
        availableMethods: NIOSSHAvailableUserAuthenticationMethods,
        nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>
    ) {
        guard availableMethods.contains(.publicKey) else {
            nextChallengePromise.fail(SSHSessionError.publicKeyAuthNotAvailable)
            return
        }

        // Offer the key once; if the server rejects it there is nothing else
        // to try, so fail the promise to end the handshake.
        let alreadyOffered = didOffer.withLockedValue { offered -> Bool in
            defer { offered = true }
            return offered
        }
        guard !alreadyOffered else {
            nextChallengePromise.fail(SSHSessionError.publicKeyAuthNotAvailable)
            return
        }

        let offer = NIOSSHUserAuthenticationOffer(
            username: username,
            serviceName: "ssh-connection",
            offer: .privateKey(.init(privateKey: privateKey))
        )
        nextChallengePromise.succeed(offer)
    }
}
