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

    public void Bind(ushort localPort)
    {
        Close();

        _client = new UdpClient(new IPEndPoint(IPAddress.Any, localPort));
        _cts = new CancellationTokenSource();
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

    private static string PreviewHex(byte[] bytes)
    {
        const int maxPreviewBytes = 64;
        var previewLength = Math.Min(bytes.Length, maxPreviewBytes);
        var hex = Convert.ToHexString(bytes.AsSpan(0, previewLength));
        return bytes.Length > maxPreviewBytes ? $"{hex}..." : hex;
    }
}
