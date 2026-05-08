import Darwin
import Foundation
import Network

public struct MdnsPeer: Equatable, Identifiable {
    public let name: String
    public let os: String
    public let version: String
    public let publicKeyFingerprint: String
    public let peerId: String
    public let hostName: String?
    public let addresses: [String]
    public let port: Int
    public let stale: Bool

    public var id: String {
        "\(peerId)|\(name)|\(hostName ?? "")|\(port)"
    }

    public var bestHost: String? {
        addresses.first(where: Self.isPrivateIPv4)
            ?? addresses.first(where: { !$0.contains(":") })
            ?? hostName
    }

    public var endpoint: NWEndpoint? {
        guard let bestHost,
              let port = NWEndpoint.Port(rawValue: UInt16(clamping: self.port))
        else { return nil }
        return .hostPort(host: .name(bestHost, nil), port: port)
    }

    public init(name: String,
                os: String,
                version: String,
                publicKeyFingerprint: String,
                peerId: String,
                hostName: String?,
                addresses: [String],
                port: Int,
                stale: Bool = false) {
        self.name = name
        self.os = os
        self.version = version
        self.publicKeyFingerprint = publicKeyFingerprint
        self.peerId = peerId
        self.hostName = hostName
        self.addresses = addresses
        self.port = port
        self.stale = stale
    }

    private static func isPrivateIPv4(_ value: String) -> Bool {
        let parts = value.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        return parts[0] == 10
            || (parts[0] == 172 && (16...31).contains(parts[1]))
            || (parts[0] == 192 && parts[1] == 168)
            || parts[0] == 169 && parts[1] == 254
    }
}

/// Advertises this device on `_barelyreal._tcp.local.` with TXT records per BRP Discovery.
public final class MdnsAdvertiser: NSObject, NetServiceDelegate {
    public static let serviceType = "_barelyreal._tcp."
    public static let domain = "local."

    private var service: NetService?
    private var onLog: ((String) -> Void)?

    public override init() {
        super.init()
    }

    public func start(deviceName: String, publicKeyFingerprint: String) {
        start(deviceName: deviceName,
              port: 24_800,
              os: "macOS",
              version: "0.1.0",
              peerId: "mac",
              publicKeyFingerprint: publicKeyFingerprint)
    }

    public func start(deviceName: String,
                      port: UInt16,
                      os: String,
                      version: String,
                      peerId: String,
                      publicKeyFingerprint: String,
                      onLog: ((String) -> Void)? = nil) {
        stop()
        self.onLog = onLog

        let serviceName = MdnsRecord.sanitizedName(deviceName)
        let service = NetService(domain: Self.domain,
                                 type: Self.serviceType,
                                 name: serviceName,
                                 port: Int32(port))
        service.delegate = self
        service.includesPeerToPeer = true
        service.setTXTRecord(MdnsRecord.txtData(
            name: serviceName,
            os: os,
            version: version,
            peerId: peerId,
            publicKeyFingerprint: publicKeyFingerprint
        ))
        service.publish()
        self.service = service
    }

    public func stop() {
        service?.stop()
        service?.delegate = nil
        service = nil
    }

    public func netServiceDidPublish(_ sender: NetService) {
        onLog?("mDNS advertised \(sender.name) on \(sender.type)\(sender.domain):\(sender.port)")
    }

    public func netService(_ sender: NetService, didNotPublish errorDict: [String: NSNumber]) {
        onLog?("mDNS advertise failed: \(errorDict)")
    }
}

public final class MdnsBrowser: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    public var onChange: (([MdnsPeer]) -> Void)?
    public var onLog: ((String) -> Void)?

    private let browser = NetServiceBrowser()
    private var servicesByKey: [String: NetService] = [:]
    private var peersByKey: [String: MdnsPeer] = [:]

    public override init() {
        super.init()
        browser.delegate = self
        browser.includesPeerToPeer = true
    }

    public func start() {
        stop()
        browser.delegate = self
        browser.includesPeerToPeer = true
        browser.searchForServices(ofType: MdnsAdvertiser.serviceType, inDomain: MdnsAdvertiser.domain)
        onLog?("mDNS browsing for \(MdnsAdvertiser.serviceType)\(MdnsAdvertiser.domain)")
    }

    public func stop() {
        browser.stop()
        for service in servicesByKey.values {
            service.stop()
            service.delegate = nil
        }
        servicesByKey.removeAll()
        peersByKey.removeAll()
        emit()
    }

    public func netServiceBrowser(_ browser: NetServiceBrowser,
                                  didFind service: NetService,
                                  moreComing: Bool) {
        let key = Self.key(for: service)
        servicesByKey[key] = service
        service.delegate = self
        service.resolve(withTimeout: 3)
        if !moreComing { emit() }
    }

    public func netServiceBrowser(_ browser: NetServiceBrowser,
                                  didRemove service: NetService,
                                  moreComing: Bool) {
        let key = Self.key(for: service)
        servicesByKey.removeValue(forKey: key)
        if let existing = peersByKey[key] {
            peersByKey[key] = MdnsPeer(
                name: existing.name,
                os: existing.os,
                version: existing.version,
                publicKeyFingerprint: existing.publicKeyFingerprint,
                peerId: existing.peerId,
                hostName: existing.hostName,
                addresses: existing.addresses,
                port: existing.port,
                stale: true
            )
        }
        if !moreComing { emit() }
    }

    public func netServiceDidResolveAddress(_ sender: NetService) {
        let key = Self.key(for: sender)
        let txt = MdnsRecord.parseTXT(sender.txtRecordData())
        let name = txt["name"] ?? sender.name
        let os = txt["os"] ?? "unknown"
        let version = txt["ver"] ?? "unknown"
        let peerId = txt["peer_id"] ?? (os.lowercased().contains("win") ? "windows" : "mac")
        let fingerprint = txt["pk"] ?? ""
        let addresses = Self.ipAddresses(from: sender)

        peersByKey[key] = MdnsPeer(
            name: name,
            os: os,
            version: version,
            publicKeyFingerprint: fingerprint,
            peerId: peerId,
            hostName: sender.hostName,
            addresses: addresses,
            port: sender.port,
            stale: false
        )
        emit()
    }

    public func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        onLog?("mDNS resolve failed for \(sender.name): \(errorDict)")
    }

    private func emit() {
        let peers = peersByKey.values.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        onChange?(peers)
    }

    private static func key(for service: NetService) -> String {
        "\(service.name)|\(service.type)|\(service.domain)"
    }

    private static func ipAddresses(from service: NetService) -> [String] {
        let values = service.addresses?.compactMap { data -> String? in
            data.withUnsafeBytes { rawBuffer -> String? in
                guard let baseAddress = rawBuffer.baseAddress else { return nil }
                let sockaddrPointer = baseAddress.assumingMemoryBound(to: sockaddr.self)
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let result = getnameinfo(
                    sockaddrPointer,
                    socklen_t(data.count),
                    &host,
                    socklen_t(host.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                )
                guard result == 0 else { return nil }
                return String(cString: host)
            }
        } ?? []

        return Array(Set(values)).sorted()
    }
}

public enum MdnsRecord {
    public static func txtData(name: String,
                               os: String,
                               version: String,
                               peerId: String,
                               publicKeyFingerprint: String) -> Data {
        NetService.data(fromTXTRecord: [
            "name": Data(sanitizedName(name).utf8),
            "os": Data(os.utf8),
            "ver": Data(version.utf8),
            "peer_id": Data(peerId.utf8),
            "pk": Data(publicKeyFingerprint.utf8),
        ])
    }

    public static func parseTXT(_ data: Data?) -> [String: String] {
        guard let data else { return [:] }
        return NetService.dictionary(fromTXTRecord: data).reduce(into: [:]) { result, pair in
            result[pair.key] = String(data: pair.value, encoding: .utf8)
        }
    }

    public static func sanitizedName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "BarelyReal" : String(trimmed.prefix(63))
    }
}
