import Foundation

/// Dev-mode guard for UDP KM input.
///
/// This is not cryptographic authentication. It prevents accidental or trivial
/// LAN injection while TLS/pairing-derived packet authentication is still pending.
public struct UdpPeerFilter: Equatable {
    public let expectedHost: String

    public init(expectedHost: String) {
        self.expectedHost = expectedHost
    }

    public var isActive: Bool {
        !Self.normalizedHost(expectedHost).isEmpty
    }

    public func allows(remoteHost: String) -> Bool {
        let expected = Self.normalizedHost(expectedHost)
        let remote = Self.normalizedHost(remoteHost)
        guard !expected.isEmpty, !remote.isEmpty else { return false }

        if expected == remote {
            return true
        }

        return Self.isLoopback(expected) && Self.isLoopback(remote)
    }

    public static func normalizedHost(_ host: String) -> String {
        var value = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.hasPrefix("[") && value.hasSuffix("]") {
            value.removeFirst()
            value.removeLast()
        }
        if value.hasPrefix("::ffff:") {
            value.removeFirst("::ffff:".count)
        }
        while value.hasSuffix(".") {
            value.removeLast()
        }
        return value
    }

    private static func isLoopback(_ host: String) -> Bool {
        host == "localhost" || host == "::1" || host.hasPrefix("127.")
    }
}
