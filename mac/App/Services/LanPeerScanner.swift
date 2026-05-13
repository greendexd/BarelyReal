import Darwin
import Foundation
import Network

final class LanPeerScanner {
    private struct LocalIPv4 {
        let interface: String
        let address: String
    }

    private let queue = DispatchQueue(label: "com.barelyreal.lan-peer-scan", qos: .utility)
    private let resultLock = NSLock()

    func scan(controlPort: UInt16, timeout: TimeInterval = 0.35, completion: @escaping ([String]) -> Void) {
        let locals = Self.localPrivateIPv4Addresses()
        let candidates = Self.candidateHosts(from: locals)

        guard !candidates.isEmpty else {
            completion([])
            return
        }

        let group = DispatchGroup()
        let semaphore = DispatchSemaphore(value: 32)
        var found = Set<String>()

        for host in candidates {
            group.enter()
            queue.async {
                semaphore.wait()
                self.probe(host: host, port: controlPort, timeout: timeout) { isOpen in
                    if isOpen {
                        self.resultLock.lock()
                        found.insert(host)
                        self.resultLock.unlock()
                    }
                    semaphore.signal()
                    group.leave()
                }
            }
        }

        group.notify(queue: queue) {
            completion(found.sorted { Self.hostSortKey($0).lexicographicallyPrecedes(Self.hostSortKey($1)) })
        }
    }

    private func probe(host: String, port: UInt16, timeout: TimeInterval, completion: @escaping (Bool) -> Void) {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            completion(false)
            return
        }

        let connection = NWConnection(host: NWEndpoint.Host(host), port: endpointPort, using: .tcp)
        let lock = NSLock()
        var completed = false

        func finish(_ success: Bool) {
            lock.lock()
            guard !completed else {
                lock.unlock()
                return
            }
            completed = true
            lock.unlock()
            connection.cancel()
            completion(success)
        }

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                finish(true)
            case .failed, .cancelled:
                finish(false)
            default:
                break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + timeout) {
            finish(false)
        }
    }

    private static func localPrivateIPv4Addresses() -> [LocalIPv4] {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return [] }
        defer { freeifaddrs(pointer) }

        var result: [LocalIPv4] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let item = cursor?.pointee {
            defer { cursor = item.ifa_next }

            guard let address = item.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET),
                  let namePointer = item.ifa_name
            else { continue }

            let flags = Int32(item.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }

            let interface = String(cString: namePointer)
            guard !interface.hasPrefix("utun"),
                  !interface.hasPrefix("awdl"),
                  !interface.hasPrefix("llw"),
                  !interface.hasPrefix("lo")
            else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let length = socklen_t(address.pointee.sa_len)
            let code = getnameinfo(address, length, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            guard code == 0 else { continue }

            let ip = String(cString: host)
            guard isPrivateIPv4(ip) else { continue }
            result.append(LocalIPv4(interface: interface, address: ip))
        }

        return result.sorted { lhs, rhs in
            interfacePriority(lhs.interface, ip: lhs.address) < interfacePriority(rhs.interface, ip: rhs.address)
        }
    }

    private static func candidateHosts(from locals: [LocalIPv4]) -> [String] {
        let ownAddresses = Set(locals.map(\.address))
        var candidates: [String] = []
        var seenPrefixes = Set<String>()

        for local in locals {
            let parts = local.address.split(separator: ".").compactMap { Int($0) }
            guard parts.count == 4 else { continue }
            let prefix = "\(parts[0]).\(parts[1]).\(parts[2])"
            guard seenPrefixes.insert(prefix).inserted else { continue }

            for lastOctet in 1...254 {
                let host = "\(prefix).\(lastOctet)"
                if !ownAddresses.contains(host) {
                    candidates.append(host)
                }
            }
        }

        return candidates
    }

    private static func isPrivateIPv4(_ value: String) -> Bool {
        let parts = value.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        return parts[0] == 10
            || (parts[0] == 172 && (16...31).contains(parts[1]))
            || (parts[0] == 192 && parts[1] == 168)
            || (parts[0] == 169 && parts[1] == 254)
    }

    private static func interfacePriority(_ interface: String, ip: String) -> Int {
        if interface == "en0" || interface == "en1" { return 0 }
        if ip.hasPrefix("192.168.") { return 1 }
        if ip.hasPrefix("172.") { return 2 }
        if ip.hasPrefix("10.") { return 3 }
        return 4
    }

    private static func hostSortKey(_ host: String) -> [Int] {
        host.split(separator: ".").map { Int($0) ?? 0 }
    }
}
