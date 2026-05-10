import CryptoKit
import Foundation

/// Per-device long-lived identity used by BRP pairing.
///
/// On first run we generate an ed25519 key pair and a derived self-signed certificate placeholder.
/// Dev builds store the private key in Application Support instead of Keychain so local testing
/// never shows a system password prompt. Public release builds should move this back to Keychain.
/// The public-key fingerprint (SHA-256) is what gets pinned by peers during PIN pairing per BRP § Pairing.
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
        case fileStore(Error)
        case fileRead(Error)
        case malformedKeyMaterial
    }

    private static let applicationSupportSubdir = "BarelyReal"
    private static let filename = "device-identity.json"

    public init() {}

    /// Load existing identity from Application Support or generate a fresh one and persist it.
    public func loadOrGenerate() throws -> Identity {
        do {
            if let existing = try loadFromDisk() {
                return existing
            }
        } catch {
            deleteFromDisk()
        }
        let fresh = generate()
        try storeOnDisk(fresh)
        return fresh
    }

    /// Force regenerate (used for unpairing all peers).
    public func regenerate() throws -> Identity {
        deleteFromDisk()
        let fresh = generate()
        try storeOnDisk(fresh)
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

    private func loadFromDisk() throws -> Identity? {
        let url = identityURL(createDirectory: false)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            let stored = try JSONDecoder().decode(StoredIdentity.self, from: data)
            guard stored.privateKeyData.count == 32 else {
                throw IdentityError.malformedKeyMaterial
            }
            let key = try Curve25519.Signing.PrivateKey(rawRepresentation: stored.privateKeyData)
            let pub = key.publicKey.rawRepresentation
            let fp = SHA256.hash(data: pub).withUnsafeBytes { Data($0) }
            return Identity(
                privateKeyData: key.rawRepresentation,
                publicKeyData: pub,
                publicKeyFingerprint: fp.base64EncodedString()
            )
        } catch let error as IdentityError {
            throw error
        } catch {
            throw IdentityError.fileRead(error)
        }
    }

    private func storeOnDisk(_ identity: Identity) throws {
        do {
            let url = identityURL(createDirectory: true)
            let stored = StoredIdentity(privateKeyData: identity.privateKeyData)
            let data = try JSONEncoder().encode(stored)
            try data.write(to: url, options: .atomic)
        } catch {
            throw IdentityError.fileStore(error)
        }
    }

    private func deleteFromDisk() {
        try? FileManager.default.removeItem(at: identityURL(createDirectory: false))
    }

    private func identityURL(createDirectory: Bool) -> URL {
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: createDirectory))
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent(Self.applicationSupportSubdir, isDirectory: true)
        if createDirectory {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent(Self.filename)
    }

    private struct StoredIdentity: Codable {
        let privateKeyData: Data
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
        var current = load().filter {
            $0.publicKeyFingerprint != peer.publicKeyFingerprint
                && $0.displayName.caseInsensitiveCompare(peer.displayName) != .orderedSame
        }
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
