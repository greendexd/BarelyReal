import Foundation
import Network

/// Advertises this device on `_barelyreal._tcp.` with TXT records per BRP § Discovery.
/// TODO(week 1): use `NWListener` with `NWParameters.tcp` + `service` to publish, and `NWBrowser`
/// to discover peers. Populate TXT (name, os, ver, pk).
public final class MdnsAdvertiser {
    public init() {}

    public func start(deviceName: String, publicKeyFingerprint: String) {
        // TODO
    }

    public func stop() {
        // TODO
    }
}

public final class MdnsBrowser {
    public struct Peer: Equatable {
        public let name: String
        public let os: String
        public let version: String
        public let publicKeyFingerprint: String
        public let endpoint: NWEndpoint
    }

    public var onChange: (([Peer]) -> Void)?

    public init() {}

    public func start() {
        // TODO
    }

    public func stop() {
        // TODO
    }
}
