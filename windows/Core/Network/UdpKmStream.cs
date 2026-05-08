using BarelyReal.Core.Protocol;
using System.Buffers.Binary;
using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;

namespace BarelyReal.Core.Network;

/// UDP socket carrying encoded KmFrame events.
public sealed class UdpKmStream : IDisposable
{
    public event Action<KmFrame>? OnFrame;
    public event Action<string>? LogLine;

    private UdpClient? _client;
    private CancellationTokenSource? _cts;
    private UdpKmSourceFilter _sourceFilter = UdpKmSourceFilter.Disabled;
    private byte[]? _authKey;
    private readonly UdpKmReplayGuard _replayGuard = new();
    private ulong _droppedFrames;
    private ulong _authFailures;
    private ulong _replayDrops;
    private DateTime _lastDropLogUtc = DateTime.MinValue;
    private DateTime _lastAuthFailureLogUtc = DateTime.MinValue;
    private DateTime _lastReplayDropLogUtc = DateTime.MinValue;

    public UdpKmStream(string? sharedSecret = null)
    {
        SetSharedSecret(sharedSecret);
    }

    public bool IsAuthenticationEnabled => _authKey is not null;

    public void SetSharedSecret(string? sharedSecret)
    {
        var trimmed = sharedSecret?.Trim();
        _authKey = string.IsNullOrWhiteSpace(trimmed) ? null : UdpKmAuthenticator.DeriveKey(trimmed);
    }

    public void Bind(ushort localPort, string? expectedPeerHost = null)
    {
        Close();

        _sourceFilter = UdpKmSourceFilter.FromHost(expectedPeerHost);
        _droppedFrames = 0;
        _authFailures = 0;
        _replayDrops = 0;
        _lastDropLogUtc = DateTime.MinValue;
        _lastAuthFailureLogUtc = DateTime.MinValue;
        _lastReplayDropLogUtc = DateTime.MinValue;
        ResetReplayProtection();
        _client = new UdpClient(new IPEndPoint(IPAddress.Any, localPort));
        _cts = new CancellationTokenSource();
        if (_sourceFilter.Enabled)
            LogLine?.Invoke($"UDP source filter enabled for {_sourceFilter.Description}");
        if (IsAuthenticationEnabled)
            LogLine?.Invoke("UDP KM authentication required (HMAC-SHA256).");
        _ = ReceiveLoopAsync(_client, _cts.Token);
    }

    public void Send(KmFrame frame, string peerHost, ushort peerPort)
    {
        var client = _client ??= new UdpClient();
        var payload = KmFrameCodec.Encode(frame);
        if (_authKey is { } authKey)
            payload = UdpKmAuthenticator.Wrap(payload, authKey);
        client.Send(payload, payload.Length, peerHost, peerPort);
    }

    public void ResetReplayProtection()
    {
        _replayGuard.Reset();
    }

    public void Close()
    {
        _cts?.Cancel();
        _client?.Dispose();
        _cts?.Dispose();
        ResetReplayProtection();

        _client = null;
        _cts = null;
    }

    public void Dispose()
    {
        Close();
    }

    private async Task ReceiveLoopAsync(UdpClient client, CancellationToken token)
    {
        try
        {
            while (!token.IsCancellationRequested)
            {
                var result = await client.ReceiveAsync(token).ConfigureAwait(false);
                if (!_sourceFilter.Allows(result.RemoteEndPoint.Address))
                {
                    LogDroppedFrame(result.RemoteEndPoint);
                    continue;
                }

                var payload = AuthenticateDatagram(result.Buffer, result.RemoteEndPoint);
                if (payload is null)
                    continue;

                LogLine?.Invoke(
                    $"UDP frame received bytes len={payload.Length} from={result.RemoteEndPoint} hex={PreviewHex(payload)}");
                try
                {
                    var frame = KmFrameCodec.Decode(payload);
                    if (IsAuthenticationEnabled && !_replayGuard.TryAccept(frame, out var replayFailure))
                    {
                        LogReplayDrop(result.RemoteEndPoint, frame, replayFailure);
                        continue;
                    }

                    OnFrame?.Invoke(frame);
                }
                catch (BrpCodecException ex)
                {
                    LogLine?.Invoke($"UDP frame decode failed: {ex.Error}");
                    // Malformed UDP datagrams are dropped. Control channel owns reconnect policy.
                }
            }
        }
        catch (OperationCanceledException)
        {
            // Expected during Close().
        }
        catch (ObjectDisposedException)
        {
            // Expected during Close().
        }
    }

    private void LogDroppedFrame(IPEndPoint remoteEndPoint)
    {
        _droppedFrames++;
        var now = DateTime.UtcNow;
        if (_droppedFrames <= 3 || _droppedFrames % 100 == 0 || now - _lastDropLogUtc >= TimeSpan.FromSeconds(30))
        {
            _lastDropLogUtc = now;
            LogLine?.Invoke(
                $"UDP frame dropped from unexpected source {remoteEndPoint}; expected {_sourceFilter.Description}; dropped={_droppedFrames}");
        }
    }

    private void LogReplayDrop(IPEndPoint remoteEndPoint, KmFrame frame, string reason)
    {
        _replayDrops++;
        var now = DateTime.UtcNow;
        if (_replayDrops <= 3 || _replayDrops % 100 == 0 || now - _lastReplayDropLogUtc >= TimeSpan.FromSeconds(30))
        {
            _lastReplayDropLogUtc = now;
            LogLine?.Invoke(
                $"UDP KM replay dropped from {remoteEndPoint}: seq={frame.Seq} type={frame.Type} reason={reason}; dropped={_replayDrops}");
        }
    }

    private byte[]? AuthenticateDatagram(byte[] datagram, IPEndPoint remoteEndPoint)
    {
        if (_authKey is not { } authKey)
        {
            if (UdpKmAuthenticator.HasMagic(datagram))
            {
                LogAuthFailure(remoteEndPoint, "authenticated envelope received but no shared secret is configured");
                return null;
            }

            return datagram;
        }

        if (!UdpKmAuthenticator.TryUnwrap(datagram, authKey, out var payload, out var failure))
        {
            LogAuthFailure(remoteEndPoint, failure);
            return null;
        }

        return payload;
    }

    private void LogAuthFailure(IPEndPoint remoteEndPoint, string reason)
    {
        _authFailures++;
        var now = DateTime.UtcNow;
        if (_authFailures <= 3 || _authFailures % 100 == 0 || now - _lastAuthFailureLogUtc >= TimeSpan.FromSeconds(30))
        {
            _lastAuthFailureLogUtc = now;
            LogLine?.Invoke(
                $"UDP KM auth failed from {remoteEndPoint}: {reason}; dropped={_authFailures}");
        }
    }

    private static string PreviewHex(byte[] bytes)
    {
        const int maxPreviewBytes = 64;
        var previewLength = Math.Min(bytes.Length, maxPreviewBytes);
        var hex = Convert.ToHexString(bytes.AsSpan(0, previewLength));
        return bytes.Length > maxPreviewBytes ? $"{hex}..." : hex;
    }
}

public sealed class UdpKmReplayGuard
{
    public const uint WindowSize = 1024;

    private readonly LaneState _flow = new();
    private readonly LaneState _input = new();

    public void Reset()
    {
        _flow.Reset();
        _input.Reset();
    }

    public bool TryAccept(KmFrame frame, out string failure)
    {
        var lane = IsFlow(frame.Type) ? _flow : _input;
        return lane.TryAccept(frame.Seq, out failure);
    }

    private static bool IsFlow(KmType type) => type is KmType.Heartbeat or KmType.ClockSync;

    private sealed class LaneState
    {
        private readonly HashSet<uint> _accepted = new();
        private bool _hasMaxSeen;
        private uint _maxSeen;

        public void Reset()
        {
            _accepted.Clear();
            _hasMaxSeen = false;
            _maxSeen = 0;
        }

        public bool TryAccept(uint seq, out string failure)
        {
            if (!_hasMaxSeen)
            {
                _hasMaxSeen = true;
                _maxSeen = seq;
                _accepted.Add(seq);
                failure = string.Empty;
                return true;
            }

            if (IsNewer(seq, _maxSeen))
            {
                _maxSeen = seq;
                Prune();
                _accepted.Add(seq);
                failure = string.Empty;
                return true;
            }

            if (IsOlderThanWindow(seq, _maxSeen))
            {
                failure = "older than replay window";
                return false;
            }

            if (!_accepted.Add(seq))
            {
                failure = "duplicate sequence";
                return false;
            }

            failure = string.Empty;
            return true;
        }

        private void Prune()
        {
            _accepted.RemoveWhere(seq => IsOlderThanWindow(seq, _maxSeen));
        }

        private static bool IsNewer(uint seq, uint maxSeen) =>
            seq != maxSeen && unchecked((int)(seq - maxSeen)) > 0;

        private static bool IsOlderThanWindow(uint seq, uint maxSeen) =>
            seq != maxSeen && !IsNewer(seq, maxSeen) && unchecked(maxSeen - seq) > WindowSize;
    }
}

public static class UdpKmAuthenticator
{
    public const int HeaderSize = 12;
    public const int TagSize = 32;
    public const byte Version = 1;
    public const byte AlgorithmHmacSha256 = 1;
    public const uint Magic = 0x4D4B5242; // ASCII "BRKM" in little-endian order.
    private static readonly byte[] KeyLabel = Encoding.UTF8.GetBytes("BarelyReal UDP KM v1\0");

    public static byte[] DeriveKey(string sharedSecret)
    {
        var secretBytes = Encoding.UTF8.GetBytes(sharedSecret.Trim());
        var input = new byte[KeyLabel.Length + secretBytes.Length];
        KeyLabel.CopyTo(input, 0);
        secretBytes.CopyTo(input, KeyLabel.Length);
        return SHA256.HashData(input);
    }

    public static bool HasMagic(ReadOnlySpan<byte> datagram) =>
        datagram.Length >= 4 && BinaryPrimitives.ReadUInt32LittleEndian(datagram[..4]) == Magic;

    public static byte[] Wrap(ReadOnlySpan<byte> payload, ReadOnlySpan<byte> key)
    {
        ArgumentOutOfRangeException.ThrowIfGreaterThan(payload.Length, int.MaxValue - HeaderSize - TagSize);

        var datagram = new byte[HeaderSize + payload.Length + TagSize];
        var span = datagram.AsSpan();
        BinaryPrimitives.WriteUInt32LittleEndian(span[..4], Magic);
        span[4] = Version;
        span[5] = AlgorithmHmacSha256;
        span[6] = 0; // flags
        span[7] = 0; // reserved
        BinaryPrimitives.WriteUInt32LittleEndian(span.Slice(8, 4), (uint)payload.Length);
        payload.CopyTo(span.Slice(HeaderSize, payload.Length));

        var tag = HMACSHA256.HashData(key, span[..^TagSize]);
        tag.CopyTo(span[^TagSize..]);
        return datagram;
    }

    public static bool TryUnwrap(
        ReadOnlySpan<byte> datagram,
        ReadOnlySpan<byte> key,
        out byte[] payload,
        out string failure)
    {
        payload = Array.Empty<byte>();

        if (datagram.Length < HeaderSize + TagSize)
        {
            failure = "truncated envelope";
            return false;
        }

        if (!HasMagic(datagram))
        {
            failure = "missing BRKM auth envelope";
            return false;
        }

        if (datagram[4] != Version)
        {
            failure = $"unsupported envelope version {datagram[4]}";
            return false;
        }

        if (datagram[5] != AlgorithmHmacSha256)
        {
            failure = $"unsupported auth algorithm {datagram[5]}";
            return false;
        }

        if (datagram[6] != 0 || datagram[7] != 0)
        {
            failure = "unsupported envelope flags";
            return false;
        }

        var payloadLength = BinaryPrimitives.ReadUInt32LittleEndian(datagram.Slice(8, 4));
        if (payloadLength > int.MaxValue)
        {
            failure = "payload length overflow";
            return false;
        }

        var expectedLength = HeaderSize + (int)payloadLength + TagSize;
        if (datagram.Length != expectedLength)
        {
            failure = "payload length mismatch";
            return false;
        }

        var expectedTag = HMACSHA256.HashData(key, datagram[..^TagSize]);
        if (!CryptographicOperations.FixedTimeEquals(expectedTag, datagram[^TagSize..]))
        {
            failure = "invalid HMAC tag";
            return false;
        }

        payload = datagram.Slice(HeaderSize, (int)payloadLength).ToArray();
        failure = string.Empty;
        return true;
    }
}

public enum UdpKmAuthenticationError
{
    TruncatedEnvelope,
    MissingEnvelope,
    UnsupportedVersion,
    UnsupportedAlgorithm,
    UnsupportedFlags,
    PayloadLengthOverflow,
    PayloadLengthMismatch,
    InvalidHmacTag
}

public sealed class UdpKmSourceFilter
{
    public static UdpKmSourceFilter Disabled { get; } = new(null, Array.Empty<IPAddress>());

    private readonly HashSet<IPAddress> _allowedAddresses;

    private UdpKmSourceFilter(string? host, IReadOnlyCollection<IPAddress> allowedAddresses)
    {
        Host = host;
        _allowedAddresses = allowedAddresses.Select(Normalize).ToHashSet();
    }

    public string? Host { get; }
    public bool Enabled => _allowedAddresses.Count > 0;
    public string Description => Enabled
        ? $"{Host} ({string.Join(", ", _allowedAddresses.Select(address => address.ToString()).Order())})"
        : "any source";

    public static UdpKmSourceFilter FromHost(string? host)
    {
        var trimmed = host?.Trim();
        if (string.IsNullOrWhiteSpace(trimmed))
            return Disabled;

        var addresses = Dns.GetHostAddresses(trimmed);
        return addresses.Length == 0
            ? throw new SocketException((int)SocketError.HostNotFound)
            : new UdpKmSourceFilter(trimmed, addresses);
    }

    public static UdpKmSourceFilter FromAddresses(string host, params IPAddress[] addresses)
    {
        return addresses.Length == 0
            ? throw new ArgumentException("At least one address is required.", nameof(addresses))
            : new UdpKmSourceFilter(host, addresses);
    }

    public bool Allows(IPAddress remoteAddress)
    {
        return !Enabled || _allowedAddresses.Contains(Normalize(remoteAddress));
    }

    private static IPAddress Normalize(IPAddress address)
    {
        return address.IsIPv4MappedToIPv6 ? address.MapToIPv4() : address;
    }
}
