import CryptoKit
import Foundation
import Security

/// Manages the P-256 private key that lives inside the iPhone's Secure
/// Enclave. Key material never leaves the enclave: only signatures come out.
///
/// Storage model: CryptoKit persists the enclave key in the keychain at
/// creation time. We keep its `dataRepresentation` (a keychain reference
/// blob, not key material) under a well-known account so the same key can be
/// reconstructed across launches.
///
/// Face ID is enforced at the app level by `BiometricAuthenticator` before
/// the key is loaded. If you instead want the enclave to demand biometry on
/// every signature, add `.biometryAny` to the access-control flags in
/// `createKey` — note that automatic reconnects will then prompt each time.
struct SecureEnclaveKeyStore {
    static let defaultKeyTag = "main"

    private let service = "com.conduit.ssh.keys"

    enum KeyStoreError: LocalizedError {
        case enclaveUnavailable
        case keyNotFound
        case keychainFailure(OSStatus)

        var errorDescription: String? {
            switch self {
            case .enclaveUnavailable:
                return "This device does not have a Secure Enclave."
            case .keyNotFound:
                return "No server key exists yet. Create one first."
            case .keychainFailure(let status):
                return "Keychain error \(status)."
            }
        }
    }

    // MARK: - Existence

    func keyExists(tag: String = defaultKeyTag) -> Bool {
        (try? loadBlob(tag: tag)) != nil
    }

    // MARK: - Creation

    /// Generates a new P-256 key inside the Secure Enclave and stores its
    /// reference blob in the keychain. Overwrites any existing key with the
    /// same tag.
    @discardableResult
    func createKey(tag: String = defaultKeyTag) throws -> P256.Signing.PublicKey {
        guard SecureEnclave.isAvailable else { throw KeyStoreError.enclaveUnavailable }

        var error: Unmanaged<CFError>?
        guard let accessControl = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [.privateKeyUsage],
            &error
        ) else {
            throw error!.takeRetainedValue() as Error
        }

        let key = try SecureEnclave.P256.Signing.PrivateKey(accessControl: accessControl)
        try storeBlob(key.dataRepresentation, tag: tag)
        return key.publicKey
    }

    // MARK: - Loading

    /// Reconstructs the CryptoKit handle for a stored enclave key. Signing
    /// happens inside the enclave; the handle is just a reference.
    func privateKey(tag: String = defaultKeyTag) throws -> SecureEnclave.P256.Signing.PrivateKey {
        let blob = try loadBlob(tag: tag)
        return try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: blob)
    }

    /// The OpenSSH `authorized_keys` line for this key, ready to paste into
    /// an EC2 instance's `~/.ssh/authorized_keys`.
    func openSSHPublicKey(tag: String = defaultKeyTag) throws -> String {
        let key = try privateKey(tag: tag)
        return SSHWireFormat.openSSHECDSAP256PublicKey(
            x963Representation: key.publicKey.x963Representation,
            comment: "conduit@ios"
        )
    }

    // MARK: - Keychain plumbing

    private func storeBlob(_ blob: Data, tag: String) throws {
        // Replace any previous blob for this tag.
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tag,
        ]
        SecItemDelete(base as CFDictionary)

        var item = base
        item[kSecValueData as String] = blob
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeyStoreError.keychainFailure(status) }
    }

    private func loadBlob(tag: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tag,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status != errSecItemNotFound else { throw KeyStoreError.keyNotFound }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeyStoreError.keychainFailure(status)
        }
        return data
    }
}
