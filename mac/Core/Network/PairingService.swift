import CryptoKit
import Foundation

/// 6-digit PIN pairing per BRP § Pairing. Derives SAS from the TLS exporter, stores pinned SPKI
/// hashes in Keychain. TODO(week 1).
public final class PairingService {
    public struct PinnedPeer: Equatable {
        public let publicKeyFingerprint: String   // base64 SHA-256 of SPKI
        public let displayName: String

        public init(publicKeyFingerprint: String, displayName: String) {
            self.publicKeyFingerprint = publicKeyFingerprint
            self.displayName = displayName
        }
    }

    public enum PinError: Error, Equatable {
        case mismatch
        case lockedOut(retryAfterSeconds: Int)
    }

    private let pinnedPeerStore: PinnedPeerStore
    private let maxWrongAttempts: Int
    private let lockoutSeconds: Int
    private var wrongAttempts = 0
    private var lockoutUntil: Date?

    public init(pinnedPeerStore: PinnedPeerStore = PinnedPeerStore(), maxWrongAttempts: Int = 5, lockoutSeconds: Int = 60) {
        self.pinnedPeerStore = pinnedPeerStore
        self.maxWrongAttempts = maxWrongAttempts
        self.lockoutSeconds = lockoutSeconds
    }

    /// Generate the 6-digit SAS from the TLS exporter output.
    /// Per spec: HKDF-Expand-Label(exporter_master_secret, "barelyreal sas", "", 4) mod 1_000_000.
    public static func sas(fromExporterBytes bytes: Data) -> String {
        precondition(bytes.count >= 4)
        let n = bytes.readLE(at: 0) as UInt32
        let pin = Int(n % 1_000_000)
        return String(format: "%06d", pin)
    }

    /// Temporary dev-mode PIN used before the real TLS exporter-backed pairing flow lands.
    /// Both sides sort their advertised public-key fingerprints so the displayed 6-digit PIN
    /// is stable no matter which machine initiates pairing.
    public static func devPairingPin(localFingerprint: String, peerFingerprint: String) -> String? {
        let fingerprints = [localFingerprint, peerFingerprint]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted()

        guard fingerprints.count == 2 else { return nil }

        let material = "barelyreal dev pairing scaffold v1\n\(fingerprints[0])\n\(fingerprints[1])"
        let digest = SHA256.hash(data: Data(material.utf8))
        return sas(fromExporterBytes: Data(digest))
    }

    public func confirm(enteredPin: String, expectedPin: String) throws {
        if let lockoutUntil {
            let remaining = Int(ceil(lockoutUntil.timeIntervalSinceNow))
            if remaining > 0 {
                throw PinError.lockedOut(retryAfterSeconds: remaining)
            }
            self.lockoutUntil = nil
            wrongAttempts = 0
        }

        guard enteredPin == expectedPin else {
            wrongAttempts += 1
            if wrongAttempts >= maxWrongAttempts {
                lockoutUntil = Date().addingTimeInterval(TimeInterval(lockoutSeconds))
                wrongAttempts = 0
                throw PinError.lockedOut(retryAfterSeconds: lockoutSeconds)
            }
            throw PinError.mismatch
        }

        wrongAttempts = 0
        lockoutUntil = nil
    }

    public func loadPinnedPeers() -> [PinnedPeer] {
        pinnedPeerStore.load()
    }

    public func pinPeer(_ peer: PinnedPeer) {
        pinnedPeerStore.add(peer)
    }

    public func unpinPeer(fingerprint: String) {
        pinnedPeerStore.remove(fingerprint: fingerprint)
    }
}
