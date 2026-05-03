using System.Buffers.Binary;
using System.Net;
using System.Net.Sockets;
using System.Text.Json;
using BarelyReal.Core.Protocol;

namespace BarelyReal.Core.Network;

public sealed class DevControlSession : IDisposable
{
    private TcpListener? _listener;
    private CancellationTokenSource? _cts;
    private string? _peerHost;
    private ushort _peerPort = 24800;

    public event Action<ScreenAnnouncement>? ScreenAnnounced;
    public event Action<LayoutSyncMessage>? LayoutSynced;
    public event Action<string>? LogLine;

    public void Start(ushort localPort = 24800, string? peerHost = null, ushort peerPort = 24800)
    {
        Close();
        _peerHost = peerHost?.Trim();
        _peerPort = peerPort;
        _cts = new CancellationTokenSource();
        _listener = new TcpListener(IPAddress.Any, localPort);
        _listener.Start();
        _ = AcceptLoop(_listener, _cts.Token);
        LogLine?.Invoke($"Control listening on TCP :{localPort}");
    }

    public void SendHello(HelloMessage hello) => SendJson(ControlType.Hello, hello);
    public void SendScreenAnnounce(ScreenAnnouncement announcement) => SendJson(ControlType.ScreenAnnounce, announcement);
    public void SendLayoutSync(LayoutSyncMessage layout) => SendJson(ControlType.LayoutSync, layout);
    public void SendKeepAlive() => Send(new ControlFrame(ControlType.KeepAlive, "{}"u8.ToArray()));

    public void Close()
    {
        _cts?.Cancel();
        _listener?.Stop();
        _cts?.Dispose();
        _cts = null;
        _listener = null;
    }

    public void Dispose() => Close();

    private async Task AcceptLoop(TcpListener listener, CancellationToken token)
    {
        try
        {
            while (!token.IsCancellationRequested)
            {
                var client = await listener.AcceptTcpClientAsync(token).ConfigureAwait(false);
                _ = Task.Run(() => HandleClient(client, token), token);
            }
        }
        catch (OperationCanceledException) { }
        catch (ObjectDisposedException) { }
        catch (Exception ex)
        {
            LogLine?.Invoke($"Control accept failed: {ex.Message}");
        }
    }

    private async Task HandleClient(TcpClient client, CancellationToken token)
    {
        using (client)
        using (var stream = client.GetStream())
        {
            try
            {
                var header = new byte[4];
                await stream.ReadExactlyAsync(header, token).ConfigureAwait(false);
                var length = BinaryPrimitives.ReadUInt32LittleEndian(header);
                if (length < 1 || length > ControlFrameCodec.MaxBodySize + 1)
                {
                    LogLine?.Invoke($"Control rejected invalid length {length}");
                    return;
                }
                var body = new byte[(int)length];
                await stream.ReadExactlyAsync(body, token).ConfigureAwait(false);
                var packet = new byte[4 + body.Length];
                BinaryPrimitives.WriteUInt32LittleEndian(packet.AsSpan(0, 4), length);
                body.CopyTo(packet.AsSpan(4));
                var (frame, _) = ControlFrameCodec.Decode(packet);
                Handle(frame);
            }
            catch (OperationCanceledException) { }
            catch (Exception ex)
            {
                LogLine?.Invoke($"Control receive failed: {ex.Message}");
            }
        }
    }

    private void Handle(ControlFrame frame)
    {
        try
        {
            switch (frame.Type)
            {
                case ControlType.ScreenAnnounce:
                    ScreenAnnounced?.Invoke(JsonSerializer.Deserialize<ScreenAnnouncement>(frame.Body)!);
                    break;
                case ControlType.LayoutSync:
                    LayoutSynced?.Invoke(JsonSerializer.Deserialize<LayoutSyncMessage>(frame.Body)!);
                    break;
                case ControlType.Hello:
                    var hello = JsonSerializer.Deserialize<HelloMessage>(frame.Body)!;
                    var peerId = hello.Os.Contains("win", StringComparison.OrdinalIgnoreCase) ? "windows" : "mac";
                    ScreenAnnounced?.Invoke(new ScreenAnnouncement(peerId, hello.Screens));
                    break;
                case ControlType.KeepAlive:
                    break;
                default:
                    LogLine?.Invoke($"Control ignored {frame.Type}");
                    break;
            }
        }
        catch (Exception ex)
        {
            LogLine?.Invoke($"Control parse failed: {ex.Message}");
        }
    }

    private void SendJson<T>(ControlType type, T value)
    {
        try
        {
            Send(new ControlFrame(type, JsonSerializer.SerializeToUtf8Bytes(value)));
        }
        catch (Exception ex)
        {
            LogLine?.Invoke($"Control encode failed: {ex.Message}");
        }
    }

    private void Send(ControlFrame frame)
    {
        var host = _peerHost;
        if (string.IsNullOrWhiteSpace(host)) return;
        _ = Task.Run(async () =>
        {
            try
            {
                using var client = new TcpClient();
                await client.ConnectAsync(host, _peerPort).ConfigureAwait(false);
                var payload = ControlFrameCodec.Encode(frame);
                await client.GetStream().WriteAsync(payload).ConfigureAwait(false);
            }
            catch (Exception ex)
            {
                LogLine?.Invoke($"Control send failed: {ex.Message}");
            }
        });
    }
}
