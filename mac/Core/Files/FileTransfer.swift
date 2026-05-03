import Foundation

/// Streams files from a drag&drop initiator to the receiving peer over the control channel
/// using FileOffer / FileChunk / FileAck / FileEnd messages. 64 KB chunks, SHA-256 per chunk.
/// TODO(week 6).
public final class FileTransfer {
    public static let chunkSize = 64 * 1024

    public init() {}

    public func send(fileURL: URL) async throws {
        // TODO: open file, emit FileOffer with name/size/sha256, stream FileChunk frames,
        // wait for FileAck, finish with FileEnd.
    }
}
