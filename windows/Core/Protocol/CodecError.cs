namespace BarelyReal.Core.Protocol;

public enum BrpCodecError
{
    Truncated,
    UnknownType,
    LengthOverflow
}

public sealed class BrpCodecException : Exception
{
    public BrpCodecError Error { get; }
    public byte? UnknownTypeByte { get; }

    public BrpCodecException(BrpCodecError error, byte? unknownTypeByte = null)
        : base($"BrpCodecError: {error}{(unknownTypeByte.HasValue ? $" 0x{unknownTypeByte:X2}" : "")}")
    {
        Error = error;
        UnknownTypeByte = unknownTypeByte;
    }
}
