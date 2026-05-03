import Foundation

public enum BrpCodecError: Error, Equatable {
    case truncated
    case unknownType(UInt8)
    case lengthOverflow
}
