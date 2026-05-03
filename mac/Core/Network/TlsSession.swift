import Foundation
import Network

/// TLS 1.3 control connection between two peers.
/// TODO(week 1): implement using NWConnection with NWProtocolTLS.Options + pinned trust evaluation
/// per docs/security.md. PairingService will provide the pinned SPKI hash for the verify-block.
public final class TlsSession {
    public enum TlsSessionError: Error, CustomStringConvertible {
        case notImplemented(String)

        public var description: String {
            switch self {
            case .notImplemented(let operation):
                return "TlsSession.\(operation) is not implemented in the current dev build"
            }
        }
    }

    public enum State {
        case idle
        case connecting
        case handshaking
        case ready
        case failed(Error)
        case closed
    }

    public private(set) var state: State = .idle

    public init() {}

    public func connect(host: String, port: UInt16) async throws {
        // TODO: NWConnection + NWProtocolTLS.Options, pinned-key verify, exporter extraction.
        throw TlsSessionError.notImplemented("connect")
    }

    public func send(_ data: Data) async throws {
        throw TlsSessionError.notImplemented("send")
    }

    public func close() {
        state = .closed
    }
}
