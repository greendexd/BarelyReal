namespace BarelyReal.Core.Files;

/// Streams files from a drag&drop initiator to the receiving peer over the control channel
/// using FileOffer / FileChunk / FileAck / FileEnd messages. 64 KB chunks, SHA-256 per chunk.
/// TODO(week 6).
public sealed class FileTransfer
{
    public const int ChunkSize = 64 * 1024;

    public Task SendAsync(string filePath, CancellationToken ct = default)
    {
        // TODO: open file, emit FileOffer with name/size/sha256, stream FileChunk frames,
        // wait for FileAck, finish with FileEnd.
        throw new NotImplementedException();
    }
}
