using System.Buffers.Binary;
using System.Text;

namespace BarelyReal.Core.Clipboard;

/// One file inside a <see cref="ClipboardFileBundle"/>.
public sealed class ClipboardFile : IEquatable<ClipboardFile>
{
    public string Name { get; }
    public byte[] Bytes { get; }

    public ClipboardFile(string name, byte[] bytes)
    {
        Name = name;
        Bytes = bytes;
    }

    public bool Equals(ClipboardFile? other)
    {
        if (other is null) return false;
        return Name == other.Name && Bytes.AsSpan().SequenceEqual(other.Bytes.AsSpan());
    }

    public override bool Equals(object? obj) => obj is ClipboardFile other && Equals(other);
    public override int GetHashCode() => HashCode.Combine(Name, Bytes.Length);
}

/// A set of files transferred together over the clipboard channel.
/// Wire format (within a clipboard frame, after the `kind = 3` byte):
///
///   u32 fileCount
///   for each file:
///     u16 nameLen
///     utf8 name           (sanitized: no path separators or NUL)
///     u64 size
///     bytes[size]
public sealed class ClipboardFileBundle : IEquatable<ClipboardFileBundle>
{
    public IReadOnlyList<ClipboardFile> Files { get; }

    public ClipboardFileBundle(IEnumerable<ClipboardFile> files)
    {
        Files = files.ToArray();
    }

    public bool Equals(ClipboardFileBundle? other)
    {
        if (other is null) return false;
        if (Files.Count != other.Files.Count) return false;
        for (var i = 0; i < Files.Count; i++)
        {
            if (!Files[i].Equals(other.Files[i])) return false;
        }
        return true;
    }

    public override bool Equals(object? obj) => obj is ClipboardFileBundle other && Equals(other);
    public override int GetHashCode() => Files.Count;
}

public enum ClipboardFileBundleError
{
    Truncated,
    TooManyFiles,
    NameTooLong,
    FileTooLarge,
    TotalTooLarge,
    InvalidName,
    InvalidUtf8
}

public sealed class ClipboardFileBundleException : Exception
{
    public ClipboardFileBundleError ErrorKind { get; }

    public ClipboardFileBundleException(ClipboardFileBundleError errorKind, string? message = null)
        : base(message ?? $"ClipboardFileBundleError: {errorKind}")
    {
        ErrorKind = errorKind;
    }
}

public static class ClipboardFileBundleCodec
{
    public const int MaxFiles = 64;
    public const int MaxNameBytes = 1024;
    public const long MaxFileBytes = 200_000_000;
    public const long MaxTotalBytes = 200_000_000;

    /// Strip any path separators / NUL / dot-segments from a file name.
    /// Returns <c>null</c> if nothing usable remains.
    public static string? SanitizeName(string raw)
    {
        if (string.IsNullOrEmpty(raw))
            return null;

        // Take only the last component if user passed a path.
        var lastSeparator = raw.LastIndexOfAny(new[] { '/', '\\' });
        var lastComponent = lastSeparator < 0 ? raw : raw[(lastSeparator + 1)..];
        var stripped = lastComponent.Replace("\0", string.Empty).Trim();
        if (stripped.Length == 0 || stripped == "." || stripped == "..")
            return null;

        var builder = new StringBuilder(stripped.Length);
        foreach (var ch in stripped)
        {
            if (ch == '/' || ch == '\\' || ch == ':')
                builder.Append('_');
            else
                builder.Append(ch);
        }
        var result = builder.ToString();
        var utf8Count = Encoding.UTF8.GetByteCount(result);
        if (utf8Count == 0 || utf8Count > MaxNameBytes)
            return null;
        return result;
    }

    public static byte[] Encode(ClipboardFileBundle bundle)
    {
        long totalSize = 4;
        foreach (var file in bundle.Files)
        {
            totalSize += 2 + Encoding.UTF8.GetByteCount(file.Name) + 8 + file.Bytes.Length;
        }
        if (totalSize > int.MaxValue)
            throw new ClipboardFileBundleException(ClipboardFileBundleError.TotalTooLarge);

        var buffer = new byte[(int)totalSize];
        var span = buffer.AsSpan();
        BinaryPrimitives.WriteUInt32LittleEndian(span[..4], (uint)bundle.Files.Count);
        var cursor = 4;
        foreach (var file in bundle.Files)
        {
            var nameBytes = Encoding.UTF8.GetBytes(file.Name);
            BinaryPrimitives.WriteUInt16LittleEndian(span.Slice(cursor, 2), (ushort)nameBytes.Length);
            cursor += 2;
            nameBytes.CopyTo(span[cursor..]);
            cursor += nameBytes.Length;
            BinaryPrimitives.WriteUInt64LittleEndian(span.Slice(cursor, 8), (ulong)file.Bytes.Length);
            cursor += 8;
            file.Bytes.CopyTo(span[cursor..]);
            cursor += file.Bytes.Length;
        }
        return buffer;
    }

    public static ClipboardFileBundle Decode(ReadOnlySpan<byte> data)
    {
        var cursor = 0;
        if (data.Length - cursor < 4)
            throw new ClipboardFileBundleException(ClipboardFileBundleError.Truncated);

        var fileCount = BinaryPrimitives.ReadUInt32LittleEndian(data.Slice(cursor, 4));
        cursor += 4;
        if (fileCount > MaxFiles)
            throw new ClipboardFileBundleException(ClipboardFileBundleError.TooManyFiles);

        var files = new List<ClipboardFile>((int)fileCount);
        long totalBytes = 0;

        for (var i = 0; i < fileCount; i++)
        {
            if (data.Length - cursor < 2)
                throw new ClipboardFileBundleException(ClipboardFileBundleError.Truncated);
            var nameLen = BinaryPrimitives.ReadUInt16LittleEndian(data.Slice(cursor, 2));
            cursor += 2;
            if (nameLen > MaxNameBytes)
                throw new ClipboardFileBundleException(ClipboardFileBundleError.NameTooLong);
            if (data.Length - cursor < nameLen)
                throw new ClipboardFileBundleException(ClipboardFileBundleError.Truncated);
            string rawName;
            try
            {
                rawName = Encoding.UTF8.GetString(data.Slice(cursor, nameLen));
            }
            catch (DecoderFallbackException)
            {
                throw new ClipboardFileBundleException(ClipboardFileBundleError.InvalidUtf8);
            }
            cursor += nameLen;
            var safeName = SanitizeName(rawName)
                ?? throw new ClipboardFileBundleException(ClipboardFileBundleError.InvalidName);

            if (data.Length - cursor < 8)
                throw new ClipboardFileBundleException(ClipboardFileBundleError.Truncated);
            var size = BinaryPrimitives.ReadUInt64LittleEndian(data.Slice(cursor, 8));
            cursor += 8;
            if (size > (ulong)MaxFileBytes)
                throw new ClipboardFileBundleException(ClipboardFileBundleError.FileTooLarge);
            totalBytes = unchecked(totalBytes + (long)size);
            if (totalBytes > MaxTotalBytes)
                throw new ClipboardFileBundleException(ClipboardFileBundleError.TotalTooLarge);

            var sizeInt = (int)size;
            if (data.Length - cursor < sizeInt)
                throw new ClipboardFileBundleException(ClipboardFileBundleError.Truncated);
            var bytes = data.Slice(cursor, sizeInt).ToArray();
            cursor += sizeInt;

            files.Add(new ClipboardFile(safeName, bytes));
        }

        return new ClipboardFileBundle(files);
    }
}
