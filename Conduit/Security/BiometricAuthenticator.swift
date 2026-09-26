import Foundation
import LocalAuthentication

/// Face ID gate in front of the Secure Enclave keys.
///
/// A successful evaluation stays fresh for `reuseWindow` seconds, so the
/// automatic reconnects that follow a network handoff don't hit the user
/// with a Face ID prompt every time. After the window lapses, the next
/// connect evaluates the policy again.
@MainActor
final class BiometricAuthenticator {
    enum BiometricError: LocalizedError {
        case unavailable(String)
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .unavailable(let reason), .failed(let reason):
                return reason
            }
        }
    }

    /// How long a Face ID success stays valid (5 minutes).
    private let reuseWindow: TimeInterval = 300
    private var lastSuccess: Date?

    func requireAuthentication(reason: String) async throws {
        if let lastSuccess, Date.now.timeIntervalSince(lastSuccess) < reuseWindow {
            return
        }

        let context = LAContext()
        var nsError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &nsError) else {
            throw BiometricError.unavailable(
                nsError?.localizedDescription ?? "Face ID is not available on this device."
            )
        }

        do {
            _ = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
            lastSuccess = .now
        } catch let error as LAError {
            // Cancellation is surfaced as-is so callers can stay silent.
            if error.code == .userCancel || error.code == .appCancel || error.code == .systemCancel {
                throw CancellationError()
            }
            throw BiometricError.failed(error.localizedDescription)
        }
    }
}
