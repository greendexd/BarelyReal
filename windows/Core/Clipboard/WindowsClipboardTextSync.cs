using System.Buffers.Binary;
using System.Drawing;
using System.Drawing.Imaging;
using System.Net;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;

namespace BarelyReal.Core.Clipboard;

public sealed class WindowsClipboardTextSync
{
    private const int MaxPayloadBytes = 220_000_000;

    private readonly string _peerHost;
    private readonly int _port;
    private readonly Action<string> _log;
    private readonly object _stateLock = new();

    private string? _lastLocalHash;
    private string? _lastAppliedRemoteHash;
    private string? _lastClipboardError;

    /// Optional sink for clipboard activity. Called for every successfully sent or received item.
    public Action<ClipboardEntry>? OnHistoryEntry { get; set; }

    public WindowsClipboardTextSync(string peerHost, int port, Action<string>? log = null)
    {
        _peerHost = peerHost;
        _port = port;
        _log = log ?? Console.WriteLine;

        var initial = WindowsClipboardNative.TryGetSnapshot(out var error);
        _lastLocalHash = initial?.Hash;
        LogClipboardError(error);
    }

    private void RecordHistory(ClipboardPacket packet)
    {
        if (OnHistoryEntry is null) return;
        try
        {
            var formatKey = packet.Kind switch
            {
                ClipboardKind.Text => "text/plain",
                ClipboardKind.Png => "image/png",
                ClipboardKind.Files => "application/x-barelyreal-files",
                _ => "application/octet-stream"
            };
            var maxBytes = 1_500_000;
            var bytes = packet.Payload.Length > maxBytes
                ? packet.Payload.AsSpan(0, maxBytes).ToArray()
                : packet.Payload;
            var hash = Convert.FromHexString(packet.Hash);
            var id = (ulong)DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
            var entry = new ClipboardEntry
            {
                Id = id,
                Formats = new Dictionary<string, byte[]> { { formatKey, bytes } },
                ContentHash = hash
            };
            OnHistoryEntry?.Invoke(entry);
        }
        catch
        {
            // History is best-effort.
        }
    }

    public async Task Run(CancellationToken cancellationToken)
    {
        var listener = new TcpListener(IPAddress.Any, _port);
        listener.Start();
        _log($"Clipboard sync listening on TCP :{_port}, peer {_peerHost}:{_port}");

        try
        {
            await Task.WhenAll(
                AcceptLoop(listener, cancellationToken),
                PollLoop(cancellationToken)).ConfigureAwait(false);
        }
        finally
        {
            listener.Stop();
        }
    }

    private async Task AcceptLoop(TcpListener listener, CancellationToken cancellationToken)
    {
        while (!cancellationToken.IsCancellationRequested)
        {
            var client = await listener.AcceptTcpClientAsync(cancellationToken).ConfigureAwait(false);
            _ = Task.Run(() => HandleClient(client, cancellationToken), cancellationToken);
        }
    }

    private async Task HandleClient(TcpClient client, CancellationToken cancellationToken)
    {
        using (client)
        using (var stream = client.GetStream())
        {
            var header = new byte[4];
            await stream.ReadExactlyAsync(header, cancellationToken).ConfigureAwait(false);

            var length = BinaryPrimitives.ReadUInt32LittleEndian(header);
            if (length < 1 || length > MaxPayloadBytes)
            {
                _log($"clipboard receive ignored: invalid length {length}");
                return;
            }

            var body = new byte[(int)length];
            await stream.ReadExactlyAsync(body, cancellationToken).ConfigureAwait(false);

            if (!Enum.IsDefined(typeof(ClipboardKind), body[0]))
            {
                _log($"clipboard receive ignored: unknown kind {body[0]}");
                return;
            }

            var kind = (ClipboardKind)body[0];
            var payload = body[1..];
            ApplyRemote(new ClipboardPacket(kind, payload));
        }
    }

    private async Task PollLoop(CancellationToken cancellationToken)
    {
        using var timer = new PeriodicTimer(TimeSpan.FromMilliseconds(200));

        while (await timer.WaitForNextTickAsync(cancellationToken).ConfigureAwait(false))
        {
            var local = WindowsClipboardNative.TryGetSnapshot(out var error);
            LogClipboardError(error);
            if (local is null)
                continue;

            var shouldSend = false;
            lock (_stateLock)
            {
                if (local.Hash != _lastLocalHash)
                {
                    _lastLocalHash = local.Hash;
                    shouldSend = local.Hash != _lastAppliedRemoteHash;
                }
            }

            if (shouldSend)
                await Send(local, cancellationToken).ConfigureAwait(false);
        }
    }

    private void ApplyRemote(ClipboardPacket packet)
    {
        var current = WindowsClipboardNative.TryGetSnapshot(out var snapshotError);
        LogClipboardError(snapshotError);
        if (current?.Hash == packet.Hash)
            return;

        string? error = null;
        bool applied;
        switch (packet.Kind)
        {
            case ClipboardKind.Text:
                applied = WindowsClipboardNative.TrySetTextWithRetry(Encoding.UTF8.GetString(packet.Payload), out error);
                break;
            case ClipboardKind.Png:
                applied = WindowsClipboardNative.TrySetPngWithRetry(packet.Payload, out error);
                break;
            case ClipboardKind.Files:
                applied = ApplyFileBundle(packet.Payload, out error);
                break;
            default:
                throw new InvalidOperationException($"Unknown clipboard kind {packet.Kind}");
        }

        if (!applied)
        {
            _log($"clipboard apply failed ({KindName(packet.Kind)}): {error ?? "unknown Windows clipboard error"}");
            return;
        }

        lock (_stateLock)
        {
            _lastAppliedRemoteHash = packet.Hash;
            _lastLocalHash = packet.Hash;
        }

        _log($"clipboard <- {Describe(packet)}");
        RecordHistory(packet);
    }

    private bool ApplyFileBundle(byte[] payload, out string? error)
    {
        ClipboardFileBundle bundle;
        try
        {
            bundle = ClipboardFileBundleCodec.Decode(payload);
        }
        catch (ClipboardFileBundleException ex)
        {
            error = $"malformed file bundle: {ex.ErrorKind}";
            return false;
        }

        if (bundle.Files.Count == 0)
        {
            error = null;
            return true;
        }

        string targetDir;
        try
        {
            var downloads = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            if (string.IsNullOrEmpty(downloads))
                downloads = Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments);
            var stamp = DateTime.Now.ToString("yyyyMMdd-HHmmss-fff");
            targetDir = Path.Combine(downloads, "Downloads", "BarelyReal", stamp);
            Directory.CreateDirectory(targetDir);
        }
        catch (Exception ex)
        {
            error = $"cannot create target directory: {ex.Message}";
            return false;
        }

        var written = new List<string>(bundle.Files.Count);
        foreach (var file in bundle.Files)
        {
            try
            {
                var dest = UniqueDestination(targetDir, file.Name);
                File.WriteAllBytes(dest, file.Bytes);
                written.Add(dest);
            }
            catch (Exception ex)
            {
                _log($"clipboard file write failed for {file.Name}: {ex.Message}");
            }
        }

        if (written.Count == 0)
        {
            error = "no files written";
            return false;
        }

        return WindowsClipboardNative.TrySetFilesWithRetry(written, out error);
    }

    private static string UniqueDestination(string directory, string proposedName)
    {
        var candidate = Path.Combine(directory, proposedName);
        if (!File.Exists(candidate))
            return candidate;

        var baseName = Path.GetFileNameWithoutExtension(proposedName);
        var ext = Path.GetExtension(proposedName);
        for (var i = 2; i < 1000; i++)
        {
            var newName = string.IsNullOrEmpty(ext)
                ? $"{baseName} ({i})"
                : $"{baseName} ({i}){ext}";
            candidate = Path.Combine(directory, newName);
            if (!File.Exists(candidate))
                return candidate;
        }
        return candidate;
    }

    private async Task Send(ClipboardPacket packet, CancellationToken cancellationToken)
    {
        if (packet.Payload.Length + 1 > MaxPayloadBytes)
        {
            _log($"clipboard send skipped: {KindName(packet.Kind)} payload too large ({packet.Payload.Length} bytes)");
            return;
        }

        try
        {
            using var client = new TcpClient();
            await client.ConnectAsync(_peerHost, _port, cancellationToken).ConfigureAwait(false);
            await using var stream = client.GetStream();

            var header = new byte[4];
            BinaryPrimitives.WriteUInt32LittleEndian(header, (uint)(packet.Payload.Length + 1));
            await stream.WriteAsync(header, cancellationToken).ConfigureAwait(false);
            await stream.WriteAsync(new[] { (byte)packet.Kind }, cancellationToken).ConfigureAwait(false);
            await stream.WriteAsync(packet.Payload, cancellationToken).ConfigureAwait(false);
            _log($"clipboard -> {Describe(packet)}");
            RecordHistory(packet);
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (SocketException ex)
        {
            _log($"clipboard send failed ({KindName(packet.Kind)}): socket {ex.SocketErrorCode}");
        }
        catch (IOException ex)
        {
            _log($"clipboard send failed ({KindName(packet.Kind)}): {ex.Message}");
        }
    }

    private void LogClipboardError(string? error)
    {
        if (string.IsNullOrWhiteSpace(error) || error == _lastClipboardError)
            return;

        _lastClipboardError = error;
        _log($"windows clipboard api error: {error}");
    }

    private static string Describe(ClipboardPacket packet)
    {
        switch (packet.Kind)
        {
            case ClipboardKind.Text:
                return $"text/plain {packet.Payload.Length} bytes hash={packet.Hash[..Math.Min(12, packet.Hash.Length)]}";
            case ClipboardKind.Png:
                return $"image/png {packet.Payload.Length} bytes hash={packet.Hash[..Math.Min(12, packet.Hash.Length)]}";
            case ClipboardKind.Files:
                try
                {
                    var bundle = ClipboardFileBundleCodec.Decode(packet.Payload);
                    return $"files ({bundle.Files.Count}) {packet.Payload.Length} bytes hash={packet.Hash[..Math.Min(12, packet.Hash.Length)]}";
                }
                catch
                {
                    return $"files {packet.Payload.Length} bytes hash={packet.Hash[..Math.Min(12, packet.Hash.Length)]}";
                }
            default:
                return $"{KindName(packet.Kind)} {packet.Payload.Length}";
        }
    }

    private static string KindName(ClipboardKind kind) =>
        kind switch
        {
            ClipboardKind.Text => "text",
            ClipboardKind.Png => "image/png",
            ClipboardKind.Files => "files",
            _ => $"kind:{(byte)kind}"
        };
    private enum ClipboardKind : byte
    {
        Text = 1,
        Png = 2,
        Files = 3
    }

    private sealed class ClipboardPacket
    {
        public ClipboardPacket(ClipboardKind kind, byte[] payload)
        {
            Kind = kind;
            Payload = payload;
            Hash = ComputeHash(kind, payload);
        }

        public ClipboardKind Kind { get; }
        public byte[] Payload { get; }
        public string Hash { get; }

        private static string ComputeHash(ClipboardKind kind, byte[] payload)
        {
            using var sha = SHA256.Create();
            sha.TransformBlock(new[] { (byte)kind }, 0, 1, null, 0);
            sha.TransformFinalBlock(payload, 0, payload.Length);
            return Convert.ToHexString(sha.Hash ?? Array.Empty<byte>());
        }
    }

    private static class WindowsClipboardNative
    {
        private const uint CF_UNICODETEXT = 13;
        private const uint CF_DIB = 8;
        private const uint CF_HDROP = 15;
        private const uint GMEM_MOVEABLE = 0x0002;
        private const uint BI_BITFIELDS = 3;
        private const uint BI_ALPHABITFIELDS = 6;

        private static readonly uint PngClipboardFormat = RegisterClipboardFormat("PNG");

        public static ClipboardPacket? TryGetSnapshot(out string? error)
        {
            error = null;

            // Files take precedence so a Cmd/Ctrl+C on a file in Finder/Explorer is preferred
            // over the auto-rendered file-name text representation.
            var bundle = TryGetFileBundle(out var bundleError);
            if (bundle is not null)
                return new ClipboardPacket(ClipboardKind.Files, ClipboardFileBundleCodec.Encode(bundle));

            var png = TryGetPng(out var pngError);
            if (png is not null)
                return new ClipboardPacket(ClipboardKind.Png, png);

            var text = TryGetText(out var textError);
            if (text is not null)
                return new ClipboardPacket(ClipboardKind.Text, Encoding.UTF8.GetBytes(text));

            error = bundleError ?? pngError ?? textError;
            return null;
        }

        private static ClipboardFileBundle? TryGetFileBundle(out string? error)
        {
            error = null;
            if (!IsClipboardFormatAvailable(CF_HDROP))
                return null;

            if (!TryOpenClipboard(out error))
                return null;

            try
            {
                var handle = GetClipboardData(CF_HDROP);
                if (handle == IntPtr.Zero)
                {
                    error = LastWin32Error("GetClipboardData(CF_HDROP)");
                    return null;
                }

                var pointer = GlobalLock(handle);
                if (pointer == IntPtr.Zero)
                {
                    error = LastWin32Error("GlobalLock(CF_HDROP)");
                    return null;
                }

                try
                {
                    var paths = ReadDropFilePaths(pointer);
                    if (paths.Count == 0)
                        return null;

                    var files = new List<ClipboardFile>(paths.Count);
                    long totalBytes = 0;
                    var skippedDirs = 0;
                    var oversize = new List<string>();
                    foreach (var path in paths.Take(ClipboardFileBundleCodec.MaxFiles))
                    {
                        try
                        {
                            var info = new FileInfo(path);
                            if (!info.Exists)
                            {
                                if (Directory.Exists(path))
                                    skippedDirs++;
                                continue;
                            }
                            if (info.Length > ClipboardFileBundleCodec.MaxFileBytes)
                            {
                                oversize.Add(info.Name);
                                continue;
                            }
                            if (totalBytes + info.Length > ClipboardFileBundleCodec.MaxTotalBytes)
                            {
                                oversize.Add(info.Name);
                                continue;
                            }
                            var safeName = ClipboardFileBundleCodec.SanitizeName(info.Name);
                            if (safeName is null)
                                continue;

                            var bytes = File.ReadAllBytes(path);
                            totalBytes += bytes.Length;
                            files.Add(new ClipboardFile(safeName, bytes));
                        }
                        catch
                        {
                            // Skip unreadable file silently; surface aggregate error if everything failed.
                        }
                    }

                    if (files.Count == 0)
                    {
                        if (skippedDirs > 0)
                            error = $"skipped {skippedDirs} directory entries (folders not supported)";
                        else if (oversize.Count > 0)
                            error = $"all source files were too large: {string.Join(", ", oversize)}";
                        return null;
                    }

                    if (skippedDirs > 0 || oversize.Count > 0)
                    {
                        var notes = new List<string>();
                        if (skippedDirs > 0) notes.Add($"{skippedDirs} dirs skipped");
                        if (oversize.Count > 0) notes.Add($"oversize: {string.Join(", ", oversize)}");
                        error = string.Join("; ", notes);
                    }

                    return new ClipboardFileBundle(files);
                }
                finally
                {
                    _ = GlobalUnlock(handle);
                }
            }
            finally
            {
                _ = CloseClipboard();
            }
        }

        public static bool TrySetFilesWithRetry(IReadOnlyList<string> paths, out string? error)
        {
            error = null;
            for (var attempt = 0; attempt < 5; attempt++)
            {
                if (TrySetFiles(paths, out error))
                    return true;
                Thread.Sleep(50);
            }
            return false;
        }

        private static bool TrySetFiles(IReadOnlyList<string> paths, out string? error)
        {
            if (!TryOpenClipboard(out error))
                return false;

            var handle = IntPtr.Zero;
            var transferred = false;
            try
            {
                if (!EmptyClipboard())
                {
                    error = LastWin32Error("EmptyClipboard");
                    return false;
                }

                handle = AllocDropFiles(paths, out error);
                if (handle == IntPtr.Zero)
                    return false;

                if (SetClipboardData(CF_HDROP, handle) == IntPtr.Zero)
                {
                    error = LastWin32Error("SetClipboardData(CF_HDROP)");
                    return false;
                }

                transferred = true;
                return true;
            }
            finally
            {
                if (!transferred && handle != IntPtr.Zero)
                    _ = GlobalFree(handle);
                _ = CloseClipboard();
            }
        }

        private static List<string> ReadDropFilePaths(IntPtr pointer)
        {
            var paths = new List<string>();
            // DROPFILES: 4 DWORDs + BOOL fNC + BOOL fWide. Total 20 bytes.
            // We only need pFiles offset (DWORD at offset 0) and fWide (BOOL at offset 16).
            var offset = Marshal.ReadInt32(pointer, 0);
            var fWide = Marshal.ReadInt32(pointer, 16) != 0;
            var listPtr = IntPtr.Add(pointer, offset);

            if (fWide)
            {
                while (true)
                {
                    var path = Marshal.PtrToStringUni(listPtr) ?? string.Empty;
                    if (path.Length == 0)
                        break;
                    paths.Add(path);
                    listPtr = IntPtr.Add(listPtr, (path.Length + 1) * 2);
                }
            }
            else
            {
                while (true)
                {
                    var path = Marshal.PtrToStringAnsi(listPtr) ?? string.Empty;
                    if (path.Length == 0)
                        break;
                    paths.Add(path);
                    listPtr = IntPtr.Add(listPtr, path.Length + 1);
                }
            }

            return paths;
        }

        private static IntPtr AllocDropFiles(IReadOnlyList<string> paths, out string? error)
        {
            // DROPFILES header is 20 bytes; followed by WCHAR* paths separated by NUL,
            // terminated by an extra NUL.
            const int headerSize = 20;
            var charCount = 0;
            foreach (var path in paths)
            {
                charCount += path.Length + 1;
            }
            charCount += 1; // final NUL

            var totalBytes = headerSize + charCount * sizeof(char);
            var bytes = new byte[totalBytes];
            // pFiles
            BinaryPrimitives.WriteInt32LittleEndian(bytes.AsSpan(0, 4), headerSize);
            // pt.x = 0, pt.y = 0
            BinaryPrimitives.WriteInt32LittleEndian(bytes.AsSpan(4, 4), 0);
            BinaryPrimitives.WriteInt32LittleEndian(bytes.AsSpan(8, 4), 0);
            // fNC = FALSE
            BinaryPrimitives.WriteInt32LittleEndian(bytes.AsSpan(12, 4), 0);
            // fWide = TRUE
            BinaryPrimitives.WriteInt32LittleEndian(bytes.AsSpan(16, 4), 1);

            var cursor = headerSize;
            foreach (var path in paths)
            {
                var pathBytes = Encoding.Unicode.GetBytes(path);
                pathBytes.CopyTo(bytes.AsSpan(cursor));
                cursor += pathBytes.Length;
                // null terminator (already zero in the new array) — skip 2 bytes.
                cursor += 2;
            }
            // final extra null already zero.

            return AllocGlobalBytes(bytes, out error);
        }

        public static bool TrySetTextWithRetry(string text, out string? error)
        {
            error = null;
            for (var attempt = 0; attempt < 5; attempt++)
            {
                if (TrySetText(text, out error))
                    return true;

                Thread.Sleep(50);
            }

            return false;
        }

        public static bool TrySetPngWithRetry(byte[] png, out string? error)
        {
            error = null;
            for (var attempt = 0; attempt < 5; attempt++)
            {
                if (TrySetPng(png, out error))
                    return true;

                Thread.Sleep(50);
            }

            return false;
        }

        private static string? TryGetText(out string? error)
        {
            error = null;
            if (!IsClipboardFormatAvailable(CF_UNICODETEXT))
                return null;

            if (!TryOpenClipboard(out error))
                return null;

            try
            {
                var handle = GetClipboardData(CF_UNICODETEXT);
                if (handle == IntPtr.Zero)
                {
                    error = LastWin32Error("GetClipboardData(CF_UNICODETEXT)");
                    return null;
                }

                var pointer = GlobalLock(handle);
                if (pointer == IntPtr.Zero)
                {
                    error = LastWin32Error("GlobalLock(CF_UNICODETEXT)");
                    return null;
                }

                try
                {
                    return Marshal.PtrToStringUni(pointer);
                }
                finally
                {
                    _ = GlobalUnlock(handle);
                }
            }
            finally
            {
                _ = CloseClipboard();
            }
        }

        private static byte[]? TryGetPng(out string? error)
        {
            error = null;

            if (PngClipboardFormat != 0 && IsClipboardFormatAvailable(PngClipboardFormat))
            {
                var png = TryCopyClipboardFormat(PngClipboardFormat, "PNG", out error);
                if (png is not null && png.Length > 0)
                    return png;
            }

            if (!IsClipboardFormatAvailable(CF_DIB))
                return null;

            var dib = TryCopyClipboardFormat(CF_DIB, "CF_DIB", out error);
            if (dib is null || dib.Length == 0)
                return null;

            return TryConvertDibToPng(dib, out error);
        }

        private static byte[]? TryCopyClipboardFormat(uint format, string formatName, out string? error)
        {
            error = null;
            if (!TryOpenClipboard(out error))
                return null;

            try
            {
                var handle = GetClipboardData(format);
                if (handle == IntPtr.Zero)
                {
                    error = LastWin32Error($"GetClipboardData({formatName})");
                    return null;
                }

                return TryCopyGlobalData(handle, formatName, out error);
            }
            finally
            {
                _ = CloseClipboard();
            }
        }

        private static bool TrySetText(string text, out string? error)
        {
            error = null;
            if (!TryOpenClipboard(out error))
                return false;

            var handle = IntPtr.Zero;
            var transferred = false;

            try
            {
                if (!EmptyClipboard())
                {
                    error = LastWin32Error("EmptyClipboard");
                    return false;
                }

                var bytes = Encoding.Unicode.GetBytes(text + '\0');
                handle = AllocGlobalBytes(bytes, out error);
                if (handle == IntPtr.Zero)
                    return false;

                if (SetClipboardData(CF_UNICODETEXT, handle) == IntPtr.Zero)
                {
                    error = LastWin32Error("SetClipboardData(CF_UNICODETEXT)");
                    return false;
                }

                transferred = true;
                return true;
            }
            finally
            {
                if (!transferred && handle != IntPtr.Zero)
                    _ = GlobalFree(handle);

                _ = CloseClipboard();
            }
        }

        private static bool TrySetPng(byte[] png, out string? error)
        {
            var dib = TryConvertPngToDib(png, out error);
            if (dib is null)
                return false;

            if (!TryOpenClipboard(out error))
                return false;

            var dibHandle = IntPtr.Zero;
            var pngHandle = IntPtr.Zero;
            var dibTransferred = false;
            var pngTransferred = false;

            try
            {
                if (!EmptyClipboard())
                {
                    error = LastWin32Error("EmptyClipboard");
                    return false;
                }

                dibHandle = AllocGlobalBytes(dib, out error);
                if (dibHandle == IntPtr.Zero)
                    return false;

                if (SetClipboardData(CF_DIB, dibHandle) == IntPtr.Zero)
                {
                    error = LastWin32Error("SetClipboardData(CF_DIB)");
                    return false;
                }

                dibTransferred = true;

                if (PngClipboardFormat != 0)
                {
                    pngHandle = AllocGlobalBytes(png, out var pngError);
                    if (pngHandle != IntPtr.Zero && SetClipboardData(PngClipboardFormat, pngHandle) != IntPtr.Zero)
                    {
                        pngTransferred = true;
                    }
                    else if (pngHandle == IntPtr.Zero)
                    {
                        error = pngError;
                    }
                }

                return true;
            }
            finally
            {
                if (!dibTransferred && dibHandle != IntPtr.Zero)
                    _ = GlobalFree(dibHandle);
                if (!pngTransferred && pngHandle != IntPtr.Zero)
                    _ = GlobalFree(pngHandle);

                _ = CloseClipboard();
            }
        }

        private static byte[]? TryConvertDibToPng(byte[] dib, out string? error)
        {
            error = null;
            try
            {
                var bmpFile = CreateBmpFileFromDib(dib, out error);
                if (bmpFile is null)
                    return null;

                using var input = new MemoryStream(bmpFile);
                using var image = Image.FromStream(input, useEmbeddedColorManagement: false, validateImageData: true);
                using var output = new MemoryStream();
                image.Save(output, ImageFormat.Png);
                return output.ToArray();
            }
            catch (Exception ex) when (ex is ArgumentException or ExternalException)
            {
                error = $"CF_DIB -> PNG failed: {ex.Message}";
                return null;
            }
        }

        private static byte[]? TryConvertPngToDib(byte[] png, out string? error)
        {
            error = null;
            try
            {
                using var input = new MemoryStream(png);
                using var image = Image.FromStream(input, useEmbeddedColorManagement: false, validateImageData: true);
                using var bitmap = new Bitmap(image);
                using var output = new MemoryStream();
                bitmap.Save(output, ImageFormat.Bmp);
                var bmp = output.ToArray();

                if (bmp.Length <= 14 || bmp[0] != 0x42 || bmp[1] != 0x4D)
                {
                    error = "PNG -> CF_DIB failed: invalid BMP encoder output";
                    return null;
                }

                return bmp[14..];
            }
            catch (Exception ex) when (ex is ArgumentException or ExternalException)
            {
                error = $"PNG -> CF_DIB failed: {ex.Message}";
                return null;
            }
        }

        private static byte[]? CreateBmpFileFromDib(byte[] dib, out string? error)
        {
            error = null;
            var dibPixelOffset = DibPixelOffset(dib, out error);
            if (dibPixelOffset is null)
                return null;

            var fileSize = checked(14 + dib.Length);
            var bmp = new byte[fileSize];
            bmp[0] = 0x42;
            bmp[1] = 0x4D;
            BinaryPrimitives.WriteUInt32LittleEndian(bmp.AsSpan(2, 4), (uint)fileSize);
            BinaryPrimitives.WriteUInt32LittleEndian(bmp.AsSpan(10, 4), (uint)(14 + dibPixelOffset.Value));
            dib.CopyTo(bmp.AsSpan(14));
            return bmp;
        }

        private static int? DibPixelOffset(byte[] dib, out string? error)
        {
            error = null;
            if (dib.Length < 4)
            {
                error = "CF_DIB is too short";
                return null;
            }

            var headerSize = BinaryPrimitives.ReadUInt32LittleEndian(dib.AsSpan(0, 4));
            if (headerSize == 12)
            {
                if (dib.Length < 12)
                {
                    error = "BITMAPCOREHEADER is truncated";
                    return null;
                }

                var bitCount = BinaryPrimitives.ReadUInt16LittleEndian(dib.AsSpan(10, 2));
                var colors = bitCount <= 8 ? 1 << bitCount : 0;
                return CheckedOffset((int)headerSize + colors * 3, dib.Length, out error);
            }

            if (headerSize < 40 || headerSize > dib.Length || dib.Length < 40)
            {
                error = $"Unsupported CF_DIB header size {headerSize}";
                return null;
            }

            var bitsPerPixel = BinaryPrimitives.ReadUInt16LittleEndian(dib.AsSpan(14, 2));
            var compression = BinaryPrimitives.ReadUInt32LittleEndian(dib.AsSpan(16, 4));
            var colorsUsed = BinaryPrimitives.ReadUInt32LittleEndian(dib.AsSpan(32, 4));
            var paletteColors = bitsPerPixel <= 8 ? (colorsUsed == 0 ? 1u << bitsPerPixel : colorsUsed) : 0;
            var extraMasks = headerSize == 40
                ? compression switch
                {
                    BI_BITFIELDS => 12,
                    BI_ALPHABITFIELDS => 16,
                    _ => 0
                }
                : 0;
            var offset = checked((int)headerSize + extraMasks + (int)paletteColors * 4);
            return CheckedOffset(offset, dib.Length, out error);
        }

        private static int? CheckedOffset(int offset, int length, out string? error)
        {
            error = null;
            if (offset < 0 || offset > length)
            {
                error = $"Invalid CF_DIB pixel offset {offset}";
                return null;
            }

            return offset;
        }

        private static byte[]? TryCopyGlobalData(IntPtr handle, string name, out string? error)
        {
            error = null;
            var size = GlobalSize(handle);
            if (size == UIntPtr.Zero || size.ToUInt64() > int.MaxValue)
            {
                error = $"GlobalSize({name}) returned invalid size {size}";
                return null;
            }

            var pointer = GlobalLock(handle);
            if (pointer == IntPtr.Zero)
            {
                error = LastWin32Error($"GlobalLock({name})");
                return null;
            }

            try
            {
                var bytes = new byte[(int)size.ToUInt64()];
                Marshal.Copy(pointer, bytes, 0, bytes.Length);
                return bytes;
            }
            finally
            {
                _ = GlobalUnlock(handle);
            }
        }

        private static IntPtr AllocGlobalBytes(byte[] bytes, out string? error)
        {
            error = null;
            var handle = GlobalAlloc(GMEM_MOVEABLE, (UIntPtr)bytes.Length);
            if (handle == IntPtr.Zero)
            {
                error = LastWin32Error("GlobalAlloc");
                return IntPtr.Zero;
            }

            var pointer = GlobalLock(handle);
            if (pointer == IntPtr.Zero)
            {
                error = LastWin32Error("GlobalLock(new)");
                _ = GlobalFree(handle);
                return IntPtr.Zero;
            }

            try
            {
                Marshal.Copy(bytes, 0, pointer, bytes.Length);
                return handle;
            }
            finally
            {
                _ = GlobalUnlock(handle);
            }
        }

        private static bool TryOpenClipboard(out string? error)
        {
            error = null;
            for (var attempt = 0; attempt < 5; attempt++)
            {
                if (OpenClipboard(IntPtr.Zero))
                    return true;

                error = LastWin32Error("OpenClipboard");
                Thread.Sleep(20);
            }

            return false;
        }

        private static string LastWin32Error(string api) =>
            $"{api} failed with Win32 error {Marshal.GetLastWin32Error()}";

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool OpenClipboard(IntPtr hWndNewOwner);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool CloseClipboard();

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool EmptyClipboard();

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool IsClipboardFormatAvailable(uint format);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern IntPtr GetClipboardData(uint uFormat);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern IntPtr SetClipboardData(uint uFormat, IntPtr hMem);

        [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        private static extern uint RegisterClipboardFormat(string lpszFormat);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr GlobalAlloc(uint uFlags, UIntPtr dwBytes);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr GlobalLock(IntPtr hMem);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool GlobalUnlock(IntPtr hMem);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern UIntPtr GlobalSize(IntPtr hMem);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr GlobalFree(IntPtr hMem);
    }
}
