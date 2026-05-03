using System.Buffers.Binary;
using BarelyReal.Core.Protocol;

namespace BarelyReal.Core.Km;

public static class KmPayload
{
    public readonly record struct MouseMove(int X, int Y);
    public readonly record struct MouseButton(byte Button, bool IsDown);
    public readonly record struct MouseScroll(int DeltaX, int DeltaY);
    public readonly record struct Key(ushort KeyCode, ulong Flags);

    public static byte[] EncodeMouseMove(MouseMove move)
    {
        var payload = new byte[8];
        BinaryPrimitives.WriteInt32LittleEndian(payload.AsSpan(0, 4), move.X);
        BinaryPrimitives.WriteInt32LittleEndian(payload.AsSpan(4, 4), move.Y);
        return payload;
    }

    public static MouseMove DecodeMouseMove(ReadOnlySpan<byte> payload)
    {
        if (payload.Length < 8)
            throw new BrpCodecException(BrpCodecError.Truncated);

        return new MouseMove(
            BinaryPrimitives.ReadInt32LittleEndian(payload[..4]),
            BinaryPrimitives.ReadInt32LittleEndian(payload.Slice(4, 4)));
    }

    public static byte[] EncodeMouseButton(MouseButton button) =>
        new[] { button.Button, button.IsDown ? (byte)1 : (byte)0 };

    public static MouseButton DecodeMouseButton(ReadOnlySpan<byte> payload)
    {
        if (payload.Length < 2)
            throw new BrpCodecException(BrpCodecError.Truncated);

        return new MouseButton(payload[0], payload[1] != 0);
    }

    public static byte[] EncodeMouseScroll(MouseScroll scroll)
    {
        var payload = new byte[8];
        BinaryPrimitives.WriteInt32LittleEndian(payload.AsSpan(0, 4), scroll.DeltaX);
        BinaryPrimitives.WriteInt32LittleEndian(payload.AsSpan(4, 4), scroll.DeltaY);
        return payload;
    }

    public static MouseScroll DecodeMouseScroll(ReadOnlySpan<byte> payload)
    {
        if (payload.Length < 8)
            throw new BrpCodecException(BrpCodecError.Truncated);

        return new MouseScroll(
            BinaryPrimitives.ReadInt32LittleEndian(payload[..4]),
            BinaryPrimitives.ReadInt32LittleEndian(payload.Slice(4, 4)));
    }

    public static byte[] EncodeKey(Key key)
    {
        var payload = new byte[10];
        BinaryPrimitives.WriteUInt16LittleEndian(payload.AsSpan(0, 2), key.KeyCode);
        BinaryPrimitives.WriteUInt64LittleEndian(payload.AsSpan(2, 8), key.Flags);
        return payload;
    }

    public static Key DecodeKey(ReadOnlySpan<byte> payload)
    {
        if (payload.Length < 10)
            throw new BrpCodecException(BrpCodecError.Truncated);

        return new Key(
            BinaryPrimitives.ReadUInt16LittleEndian(payload[..2]),
            BinaryPrimitives.ReadUInt64LittleEndian(payload.Slice(2, 8)));
    }

    public static byte[] EncodeModifiers(ulong flags)
    {
        var payload = new byte[8];
        BinaryPrimitives.WriteUInt64LittleEndian(payload, flags);
        return payload;
    }

    public static ulong DecodeModifiers(ReadOnlySpan<byte> payload)
    {
        if (payload.Length < 8)
            throw new BrpCodecException(BrpCodecError.Truncated);

        return BinaryPrimitives.ReadUInt64LittleEndian(payload[..8]);
    }
}
