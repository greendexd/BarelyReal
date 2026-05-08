using BarelyReal.Core.Protocol;
using System.Net;
using System.Net.Sockets;

namespace BarelyReal.Core.Network;

/// UDP socket carrying encoded KmFrame events.
/// TODO: wrap frames in AEAD once TlsSession exposes exporter-derived key material.
public sealed class UdpKmStream : IDisposable
{
    public event Action<KmFrame>? OnFrame;
    public event Action<string>? LogLine;

    private UdpClient? _client;
    private CancellationTokenSource? _cts;
    private UdpKmSourceFilter _sourceFilter = UdpKmSourceFilter.Disabled;
    private ulong _droppedFrames;
    private DateTime _lastDropLogUtc = DateTime.MinValue;

    public void Bind(ushort localPort, string? expectedPeerHost = null)
    {
        Close();

        _sourceFilter = UdpKmSourceFilter.FromHost(expectedPeerHost);
        _droppedFrames = 0;
        _lastDropLogUtc = DateTime.MinValue;
        _client = new UdpClient(new IPEndPoint(IPAddress.Any, localPort));
        _cts = new CancellationTokenSource();
        if (_sourceFilter.Enabled)
            LogLine?.Invoke($"UDP source filter enabled for {_sourceFilter.Description}");
        _ = ReceiveLoopAsync(_client, _cts.Token);
    }

    public void Send(KmFrame frame, string peerHost, ushort peerPort)
    {
        var client = _client ??= new UdpClient();
        var payload = KmFrameCodec.Encode(frame);
        client.Send(payload, payload.Length, peerHost, peerPort);
    }

    public void Close()
    {
        _cts?.Cancel();
        _client?.Dispose();
        _cts?.Dispose();

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

                LogLine?.Invoke(
                    $"UDP frame received raw bytes len={result.Buffer.Length} from={result.RemoteEndPoint} hex={PreviewHex(result.Buffer)}");
                try
                {
                    OnFrame?.Invoke(KmFrameCodec.Decode(result.Buffer));
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

    private static string PreviewHex(byte[] bytes)
    {
        const int maxPreviewBytes = 64;
        var previewLength = Math.Min(bytes.Length, maxPreviewBytes);
        var hex = Convert.ToHexString(bytes.AsSpan(0, previewLength));
        return bytes.Length > maxPreviewBytes ? $"{hex}..." : hex;
    }
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
