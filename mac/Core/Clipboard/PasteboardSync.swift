import Foundation
import AppKit

/// Mirrors NSPasteboard changes to the peer and applies inbound clipboard frames locally.
/// Polls `NSPasteboard.general.changeCount` at 50 ms intervals (no native event API on macOS).
/// TODO(week 5).
public final class PasteboardSync {
    public var onLocalChange: ((ClipboardEntry) -> Void)?

    public init() {}

    public func start() {
        // TODO: timer poll changeCount, on change snapshot pasteboard items.
    }

    public func stop() {
        // TODO
    }

    public func applyRemote(_ entry: ClipboardEntry) {
        // TODO: write to NSPasteboard, set "echo guard" hash to suppress feedback loop.
    }
}

public struct ClipboardEntry: Equatable, Codable {
    public let id: UInt64
    public let formats: [String: Data]   // "text/plain" → utf8 bytes, "image/png" → png bytes, etc.
    public let contentHash: Data         // SHA-256 over canonicalized payload, used for dedup

    public init(id: UInt64, formats: [String: Data], contentHash: Data) {
        self.id = id
        self.formats = formats
        self.contentHash = contentHash
    }
}
