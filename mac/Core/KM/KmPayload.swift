import Foundation

public enum KmPayload {
    public struct MouseMove: Equatable {
        public let x: Int32
        public let y: Int32

        public init(x: Int32, y: Int32) {
            self.x = x
            self.y = y
        }
    }

    public struct MouseButton: Equatable {
        public let button: UInt8
        public let isDown: Bool

        public init(button: UInt8, isDown: Bool) {
            self.button = button
            self.isDown = isDown
        }
    }

    public struct MouseScroll: Equatable {
        public let deltaX: Int32
        public let deltaY: Int32

        public init(deltaX: Int32, deltaY: Int32) {
            self.deltaX = deltaX
            self.deltaY = deltaY
        }
    }

    public struct Key: Equatable {
        public let keyCode: UInt16
        public let flags: UInt64

        public init(keyCode: UInt16, flags: UInt64) {
            self.keyCode = keyCode
            self.flags = flags
        }
    }

    public static func encodeMouseMove(_ move: MouseMove) -> Data {
        var data = Data(capacity: 8)
        data.appendLE(move.x)
        data.appendLE(move.y)
        return data
    }

    public static func decodeMouseMove(_ data: Data) throws -> MouseMove {
        guard data.count >= 8 else { throw BrpCodecError.truncated }
        return MouseMove(x: data.readLE(at: 0), y: data.readLE(at: 4))
    }

    public static func encodeMouseButton(_ button: MouseButton) -> Data {
        return Data([button.button, button.isDown ? 1 : 0])
    }

    public static func decodeMouseButton(_ data: Data) throws -> MouseButton {
        guard data.count >= 2 else { throw BrpCodecError.truncated }
        return MouseButton(button: data.readU8(at: 0), isDown: data.readU8(at: 1) != 0)
    }

    public static func encodeMouseScroll(_ scroll: MouseScroll) -> Data {
        var data = Data(capacity: 8)
        data.appendLE(scroll.deltaX)
        data.appendLE(scroll.deltaY)
        return data
    }

    public static func decodeMouseScroll(_ data: Data) throws -> MouseScroll {
        guard data.count >= 8 else { throw BrpCodecError.truncated }
        return MouseScroll(deltaX: data.readLE(at: 0), deltaY: data.readLE(at: 4))
    }

    public static func encodeKey(_ key: Key) -> Data {
        var data = Data(capacity: 10)
        data.appendLE(key.keyCode)
        data.appendLE(key.flags)
        return data
    }

    public static func decodeKey(_ data: Data) throws -> Key {
        guard data.count >= 10 else { throw BrpCodecError.truncated }
        return Key(keyCode: data.readLE(at: 0), flags: data.readLE(at: 2))
    }

    public static func encodeModifiers(flags: UInt64) -> Data {
        var data = Data(capacity: 8)
        data.appendLE(flags)
        return data
    }

    public static func decodeModifiers(_ data: Data) throws -> UInt64 {
        guard data.count >= 8 else { throw BrpCodecError.truncated }
        return data.readLE(at: 0)
    }
}
