import Foundation

public enum KmType: UInt8, Equatable {
    case mouseMoveRel = 0x01
    case mouseMoveAbs = 0x02
    case mouseButton = 0x03
    case mouseScroll = 0x04
    case keyDown = 0x05
    case keyUp = 0x06
    case modifiersChanged = 0x07
    case heartbeat = 0xFE
    case clockSync = 0xFF
}

public struct KmFrame: Equatable {
    public let seq: UInt32
    public let timestampUs: UInt64
    public let type: KmType
    public let payload: Data

    public init(seq: UInt32, timestampUs: UInt64, type: KmType, payload: Data = Data()) {
        self.seq = seq
        self.timestampUs = timestampUs
        self.type = type
        self.payload = payload
    }
}

public enum KmFrameCodec {
    public static let headerSize = 13

    public static func encode(_ frame: KmFrame) -> Data {
        var data = Data(capacity: headerSize + frame.payload.count)
        data.appendLE(frame.seq)
        data.appendLE(frame.timestampUs)
        data.append(frame.type.rawValue)
        data.append(frame.payload)
        return data
    }

    public static func decode(_ data: Data) throws -> KmFrame {
        guard data.count >= headerSize else { throw BrpCodecError.truncated }
        let seq: UInt32 = data.readLE(at: 0)
        let ts: UInt64 = data.readLE(at: 4)
        let typeRaw = data.readU8(at: 12)
        guard let type = KmType(rawValue: typeRaw) else {
            throw BrpCodecError.unknownType(typeRaw)
        }
        let payloadStart = data.startIndex + headerSize
        let payload = Data(data[payloadStart..<data.endIndex])
        return KmFrame(seq: seq, timestampUs: ts, type: type, payload: payload)
    }
}
