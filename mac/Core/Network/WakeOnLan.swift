import Foundation
import Network

public enum WakeOnLanError: Error, Equatable {
    case invalidMacAddress(String)
    case invalidPort(UInt16)
}

public enum WakeOnLan {
    public static func magicPacket(macAddress: String) throws -> Data {
        let bytes = try parseMacAddress(macAddress)
        var packet = Data(repeating: 0xFF, count: 6)
        for _ in 0..<16 {
            packet.append(contentsOf: bytes)
        }
        return packet
    }

    public static func send(macAddress: String, broadcastHost: String, port: UInt16 = 9) throws {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            throw WakeOnLanError.invalidPort(port)
        }
        let packet = try magicPacket(macAddress: macAddress)
        let connection = NWConnection(
            host: NWEndpoint.Host(broadcastHost),
            port: endpointPort,
            using: .udp
        )
        connection.stateUpdateHandler = { state in
            if case .ready = state {
                connection.send(content: packet, completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        }
        connection.start(queue: DispatchQueue(label: "com.barelyreal.wol-send"))
    }

    private static func parseMacAddress(_ raw: String) throws -> [UInt8] {
        let cleaned = raw
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard cleaned.count == 12 else {
            throw WakeOnLanError.invalidMacAddress(raw)
        }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(6)
        var index = cleaned.startIndex
        for _ in 0..<6 {
            let next = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index..<next], radix: 16) else {
                throw WakeOnLanError.invalidMacAddress(raw)
            }
            bytes.append(byte)
            index = next
        }
        return bytes
    }
}
