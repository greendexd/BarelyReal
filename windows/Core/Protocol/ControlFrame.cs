using System.Buffers.Binary;

namespace BarelyReal.Core.Protocol;

public enum ControlType : byte
{
    Hello = 0x01,
    LayoutSync = 0x02,
    RoleSwitch = 0x03,
    OwnershipTransfer = 0x04,
    ScreenAnnounce = 0x05,
    WakeOnLanRequest = 0x06,
    Hotkey = 0x07,
    ClipboardOffer = 0x10,
    ClipboardRequest = 0x11,
    ClipboardData = 0x12,
    FileOffer = 0x20,
    FileChunk = 0x21,
    FileAck = 0x22,
    FileEnd = 0x23,
    KeepAlive = 0xF0,
    Bye = 0xF1
}

public sealed class ControlFrame : IEquatable<ControlFrame>
{
    public ControlType Type { get; }
    public byte[] Body { get; }

    public ControlFrame(ControlType type, byte[]? body = null)
    {
        Type = type;
        Body = body ?? Array.Empty<byte>();
    }

    public bool Equals(ControlFrame? other)
    {
        if (other is null) return false;
        return Type == other.Type && Body.AsSpan().SequenceEqual(other.Body.AsSpan());
    }

    public override bool Equals(object? obj) => obj is ControlFrame other && Equals(other);
    public override int GetHashCode() => HashCode.Combine(Type, Body.Length);
}

public static class ControlFrameCodec
{
    /// Maximum frame body size accepted by the decoder. Prevents huge-allocation DoS.
    public const int MaxBodySize = 16 * 1024 * 1024;

    public static byte[] Encode(ControlFrame frame)
    {
        if (frame.Body.Length > MaxBodySize)
            throw new ArgumentException($"Body exceeds {MaxBodySize}", nameof(frame));

        var length = (uint)(1 + frame.Body.Length);
        var buf = new byte[4 + length];
        var span = buf.AsSpan();
        BinaryPrimitives.WriteUInt32LittleEndian(span[..4], length);
        span[4] = (byte)frame.Type;
        if (frame.Body.Length > 0)
        {
            frame.Body.AsSpan().CopyTo(span[5..]);
        }
        return buf;
    }

    /// Decode one frame from a buffer. Returns the frame and the number of bytes consumed.
    /// Throws <see cref="BrpCodecException"/> with <see cref="BrpCodecError.Truncated"/> if a
    /// complete frame is not yet available — caller should read more bytes and retry.
    public static (ControlFrame Frame, int Consumed) Decode(ReadOnlySpan<byte> data)
    {
        if (data.Length < 4)
            throw new BrpCodecException(BrpCodecError.Truncated);

        var length = BinaryPrimitives.ReadUInt32LittleEndian(data[..4]);
        if (length < 1)
            throw new BrpCodecException(BrpCodecError.Truncated);

        var bodyLen = (int)length - 1;
        if (bodyLen > MaxBodySize)
            throw new BrpCodecException(BrpCodecError.LengthOverflow);

        var totalSize = 4 + (int)length;
        if (data.Length < totalSize)
            throw new BrpCodecException(BrpCodecError.Truncated);

        var typeRaw = data[4];
        if (!Enum.IsDefined(typeof(ControlType), typeRaw))
            throw new BrpCodecException(BrpCodecError.UnknownType, typeRaw);

        var body = data.Slice(5, bodyLen).ToArray();
        return (new ControlFrame((ControlType)typeRaw, body), totalSize);
    }
}
