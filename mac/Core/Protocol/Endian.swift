import Foundation

extension Data {
    public mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
    }

    public func readLE<T: FixedWidthInteger>(at offset: Int) -> T {
        precondition(offset + MemoryLayout<T>.size <= count, "readLE out of bounds")
        return withUnsafeBytes { raw -> T in
            T(littleEndian: raw.loadUnaligned(fromByteOffset: offset, as: T.self))
        }
    }

    public func readU8(at offset: Int) -> UInt8 {
        precondition(offset < count, "readU8 out of bounds")
        return withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt8.self) }
    }
}
