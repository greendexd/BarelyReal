import CryptoKit
import Foundation

public enum UdpKmAuthenticationError: Error, Equatable, CustomStringConvertible {
    case missingEnvelope
    case truncated
    case unsupportedVersion(UInt8)
    case unsupportedAlgorithm(UInt8)
    case invalidLength
    case invalidTag

    public var description: String {
        switch self {
        case .missingEnvelope: "missing authenticated UDP envelope"
        case .truncated: "truncated authenticated UDP envelope"
        case .unsupportedVersion(let version): "unsupported authenticated UDP version \(version)"
        case .unsupportedAlgorithm(let algorithm): "unsupported authenticated UDP algorithm \(algorithm)"
        case .invalidLength: "invalid authenticated UDP payload length"
        case .invalidTag: "invalid authenticated UDP tag"
        }
    }
}

public struct UdpKmAuthenticator: Equatable {
    public static let magic = Data([0x42, 0x52, 0x4B, 0x4D]) // "BRKM"
    public static let version: UInt8 = 1
    public static let hmacSha256Algorithm: UInt8 = 1
    public static let headerSize = 12
    public static let tagSize = 32

    private let key: SymmetricKey

    public init?(sharedSecret: String) {
        let normalized = sharedSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        var material = Data("BarelyReal UDP KM v1\0".utf8)
        material.append(Data(normalized.utf8))
        let digest = SHA256.hash(data: material)
        key = SymmetricKey(data: Data(digest))
    }

    public func seal(_ innerFrame: Data) -> Data {
        var header = Data(capacity: Self.headerSize)
        header.append(Self.magic)
        header.append(Self.version)
        header.append(Self.hmacSha256Algorithm)
        header.appendLE(UInt16(0)) // flags
        header.appendLE(UInt32(innerFrame.count))

        var authenticated = header
        authenticated.append(innerFrame)
        let tag = HMAC<SHA256>.authenticationCode(for: authenticated, using: key)

        var envelope = authenticated
        envelope.append(contentsOf: tag)
        return envelope
    }

    public func open(_ envelope: Data) throws -> Data {
        guard envelope.count >= Self.headerSize + Self.tagSize else {
            throw UdpKmAuthenticationError.truncated
        }
        guard envelope.prefix(Self.magic.count) == Self.magic else {
            throw UdpKmAuthenticationError.missingEnvelope
        }

        let version = envelope.readU8(at: 4)
        guard version == Self.version else {
            throw UdpKmAuthenticationError.unsupportedVersion(version)
        }

        let algorithm = envelope.readU8(at: 5)
        guard algorithm == Self.hmacSha256Algorithm else {
            throw UdpKmAuthenticationError.unsupportedAlgorithm(algorithm)
        }

        let innerLength: UInt32 = envelope.readLE(at: 8)
        let expectedLength = Self.headerSize + Int(innerLength) + Self.tagSize
        guard expectedLength == envelope.count else {
            throw UdpKmAuthenticationError.invalidLength
        }

        let signedEnd = Self.headerSize + Int(innerLength)
        let signed = envelope.prefix(signedEnd)
        let receivedTag = envelope.suffix(Self.tagSize)
        let expectedTag = Data(HMAC<SHA256>.authenticationCode(for: signed, using: key))
        guard Self.constantTimeEqual(expectedTag, Data(receivedTag)) else {
            throw UdpKmAuthenticationError.invalidTag
        }

        return Data(envelope[Self.headerSize..<signedEnd])
    }

    private static func constantTimeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var diff: UInt8 = 0
        for (left, right) in zip(lhs, rhs) {
            diff |= left ^ right
        }
        return diff == 0
    }
}
