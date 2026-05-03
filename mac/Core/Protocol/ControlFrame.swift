import Foundation

public enum ControlType: UInt8, Equatable {
    case hello = 0x01
    case layoutSync = 0x02
    case roleSwitch = 0x03
    case ownershipTransfer = 0x04
    case screenAnnounce = 0x05
    case wakeOnLanRequest = 0x06
    case hotkey = 0x07
    case clipboardOffer = 0x10
    case clipboardRequest = 0x11
    case clipboardData = 0x12
    case fileOffer = 0x20
    case fileChunk = 0x21
    case fileAck = 0x22
    case fileEnd = 0x23
    case keepAlive = 0xF0
    case bye = 0xF1
}

public struct ControlFrame: Equatable {
    public let type: ControlType
    public let body: Data

    public init(type: ControlType, body: Data = Data()) {
        self.type = type
        self.body = body
    }
}

public enum ControlFrameCodec {
    /// Maximum frame body size accepted by the decoder. Prevents huge-allocation DoS.
    /// Files and clipboards above this go on dedicated sub-streams chunked accordingly.
    public static let maxBodySize: Int = 16 * 1024 * 1024

    public static func encode(_ frame: ControlFrame) -> Data {
        let bodyLen = frame.body.count
        precondition(bodyLen <= maxBodySize, "ControlFrame body exceeds max size")
        let length = UInt32(1 + bodyLen)
        var data = Data(capacity: 4 + Int(length))
        data.appendLE(length)
        data.append(frame.type.rawValue)
        data.append(frame.body)
        return data
    }

    /// Decode one frame from a buffer. Returns the frame and the number of bytes consumed.
    /// If `data` does not yet contain a complete frame, throws `truncated` (caller should
    /// read more bytes and retry).
    public static func decode(_ data: Data) throws -> (frame: ControlFrame, consumed: Int) {
        guard data.count >= 4 else { throw BrpCodecError.truncated }
        let length: UInt32 = data.readLE(at: 0)
        guard length >= 1 else { throw BrpCodecError.truncated }
        let bodyLen = Int(length) - 1
        guard bodyLen <= maxBodySize else { throw BrpCodecError.lengthOverflow }
        let totalSize = 4 + Int(length)
        guard data.count >= totalSize else { throw BrpCodecError.truncated }
        let typeRaw = data.readU8(at: 4)
        guard let type = ControlType(rawValue: typeRaw) else {
            throw BrpCodecError.unknownType(typeRaw)
        }
        let bodyStart = data.startIndex + 5
        let bodyEnd = data.startIndex + totalSize
        let body = Data(data[bodyStart..<bodyEnd])
        return (ControlFrame(type: type, body: body), totalSize)
    }
}
