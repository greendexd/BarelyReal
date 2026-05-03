import CryptoKit
import Foundation
import Security

/// Per-device long-lived identity used by BRP pairing.
///
/// On first run we generate an ed25519 key pair and a derived self-signed certificate placeholder.
/// The private key is stored in the macOS Keychain (generic password slot, accessible only when
/// unlocked, not synced to iCloud). The public-key fingerprint (SHA-256) is what gets pinned by
/// peers during PIN pairing per BRP § Pairing.
///
/// This type is the foundation: it gives us a stable identity across launches. The actual TLS
/// 1.3 handshake and certificate wrapping live in `TlsSession` (still a stub).
public final class DeviceIdentity {
    public struct Identity {
        public let privateKeyData: Data        // Curve25519.Signing.PrivateKey raw representation
        public let publicKeyData: Data         // 32-byte raw ed25519 public key
        public let publicKeyFingerprint: String // base64(SHA-256(publicKeyData))
    }

    public enum IdentityError: Error {
        case keychainStore(OSStatus)
        case keychainRead(OSStatus)
        case malformedKeyMaterial
    }

    private static let service = "com.barelyreal.mac"
    private static let account = "device-identity-v1"

    public init() {}

    /// Load existing identity from Keychain or generate a fresh one and persist it.
    public func loadOrGenerate() throws -> Identity {
        if let existing = try loadFromKeychain() {
            return existing
        }
        let fresh = generate()
        try storeInKeychain(fresh)
        return fresh
    }

    /// Force regenerate (used for unpairing all peers).
    public func regenerate() throws -> Identity {
        deleteFromKeychain()
        let fresh = generate()
        try storeInKeychain(fresh)
        return fresh
    }

    // MARK: - private

    private func generate() -> Identity {
        let key = Curve25519.Signing.PrivateKey()
        let priv = key.rawRepresentation
        let pub = key.publicKey.rawRepresentation
        let fp = SHA256.hash(data: pub).withUnsafeBytes { Data($0) }
        return Identity(
            privateKeyData: priv,
            publicKeyData: pub,
            publicKeyFingerprint: fp.base64EncodedString()
        )
    }

    private func loadFromKeychain() throws -> Identity? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data, data.count == 32 else {
                throw IdentityError.malformedKeyMaterial
            }
            do {
                let key = try Curve25519.Signing.PrivateKey(rawRepresentation: data)
                let pub = key.publicKey.rawRepresentation
                let fp = SHA256.hash(data: pub).withUnsafeBytes { Data($0) }
                return Identity(
                    privateKeyData: key.rawRepresentation,
                    publicKeyData: pub,
                    publicKeyFingerprint: fp.base64EncodedString()
                )
            } catch {
                throw IdentityError.malformedKeyMaterial
            }
        case errSecItemNotFound:
            return nil
        default:
            throw IdentityError.keychainRead(status)
        }
    }

    private func storeInKeychain(_ identity: Identity) throws {
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecValueData as String: identity.privateKeyData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        ]
        deleteFromKeychain()
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status != errSecSuccess {
            throw IdentityError.keychainStore(status)
        }
    }

    private func deleteFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// Persistent set of pinned peer public-key fingerprints.
public final class PinnedPeerStore {
    private let url: URL

    public init(applicationSupportSubdir: String = "BarelyReal", filename: String = "pinned-peers.json") {
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent(applicationSupportSubdir, isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        self.url = dir.appendingPathComponent(filename)
    }

    public func load() -> [PairingService.PinnedPeer] {
        guard let data = try? Data(contentsOf: url),
              let array = try? JSONDecoder().decode([Stored].self, from: data) else {
            return []
        }
        return array.map { PairingService.PinnedPeer(publicKeyFingerprint: $0.fp, displayName: $0.name) }
    }

    public func save(_ peers: [PairingService.PinnedPeer]) {
        let stored = peers.map { Stored(fp: $0.publicKeyFingerprint, name: $0.displayName) }
        if let data = try? JSONEncoder().encode(stored) {
            try? data.write(to: url, options: .atomic)
        }
    }

    public func add(_ peer: PairingService.PinnedPeer) {
        var current = load().filter { $0.publicKeyFingerprint != peer.publicKeyFingerprint }
        current.append(peer)
        save(current)
    }

    public func remove(fingerprint: String) {
        let current = load().filter { $0.publicKeyFingerprint != fingerprint }
        save(current)
    }

    private struct Stored: Codable {
        let fp: String
        let name: String
    }
}
