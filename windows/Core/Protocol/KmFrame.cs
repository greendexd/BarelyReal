using System.Buffers.Binary;

namespace BarelyReal.Core.Protocol;

public enum KmType : byte
{
    MouseMoveRel = 0x01,
    MouseMoveAbs = 0x02,
    MouseButton = 0x03,
    MouseScroll = 0x04,
    KeyDown = 0x05,
    KeyUp = 0x06,
    ModifiersChanged = 0x07,
    Heartbeat = 0xFE,
    ClockSync = 0xFF
}

public sealed class KmFrame : IEquatable<KmFrame>
{
    public uint Seq { get; }
    public ulong TimestampUs { get; }
    public KmType Type { get; }
    public byte[] Payload { get; }

    public KmFrame(uint seq, ulong timestampUs, KmType type, byte[]? payload = null)
    {
        Seq = seq;
        TimestampUs = timestampUs;
        Type = type;
        Payload = payload ?? Array.Empty<byte>();
    }

    public bool Equals(KmFrame? other)
    {
        if (other is null) return false;
        return Seq == other.Seq
            && TimestampUs == other.TimestampUs
            && Type == other.Type
            && Payload.AsSpan().SequenceEqual(other.Payload.AsSpan());
    }

    public override bool Equals(object? obj) => obj is KmFrame other && Equals(other);
    public override int GetHashCode() => HashCode.Combine(Seq, TimestampUs, Type, Payload.Length);
}

public static class KmFrameCodec
{
    public const int HeaderSize = 13;

    public static byte[] Encode(KmFrame frame)
    {
        var buf = new byte[HeaderSize + frame.Payload.Length];
        var span = buf.AsSpan();
        BinaryPrimitives.WriteUInt32LittleEndian(span[..4], frame.Seq);
        BinaryPrimitives.WriteUInt64LittleEndian(span.Slice(4, 8), frame.TimestampUs);
        span[12] = (byte)frame.Type;
        if (frame.Payload.Length > 0)
        {
            frame.Payload.AsSpan().CopyTo(span[HeaderSize..]);
        }
        return buf;
    }

    public static KmFrame Decode(ReadOnlySpan<byte> data)
    {
        if (data.Length < HeaderSize)
            throw new BrpCodecException(BrpCodecError.Truncated);

        var seq = BinaryPrimitives.ReadUInt32LittleEndian(data[..4]);
        var ts = BinaryPrimitives.ReadUInt64LittleEndian(data.Slice(4, 8));
        var typeRaw = data[12];

        if (!Enum.IsDefined(typeof(KmType), typeRaw))
            throw new BrpCodecException(BrpCodecError.UnknownType, typeRaw);

        var payload = data[HeaderSize..].ToArray();
        return new KmFrame(seq, ts, (KmType)typeRaw, payload);
    }
}
