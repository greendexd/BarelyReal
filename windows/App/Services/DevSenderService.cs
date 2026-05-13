using BarelyReal.Core.Km;
using BarelyReal.Core.Layout;
using BarelyReal.Core.Network;
using BarelyReal.Core.Protocol;

namespace BarelyReal.App.Services;

/// Captures local KM events (LowLevelHooks) and streams them to a Mac receiver over UDP.
/// Mirrors mac/App/Services/MacKmSession.swift on the Windows side.
internal sealed class DevSenderService : IDisposable
{
    private readonly object _gate = new();
    private LowLevelHooks? _hooks;
    private UdpKmStream? _stream;
    private WindowsEdgeBridge? _bridge;
    private HotkeyManager? _hotkey;
    private System.Threading.Timer? _heartbeatTimer;
    private uint _heartbeatSeq = 1_000_000_000;
    private DateTime _lastFrameSentAt = DateTime.MinValue;
    private DateTime _lastStatsChangedUtc = DateTime.MinValue;

    public event Action<string>? LogLine;
    public event Action? StatsChanged;

    public bool IsRunning { get; private set; }
    public string PeerHost { get; private set; } = string.Empty;
    public ushort PeerPort { get; private set; }
    public bool KmAuthEnabled { get; private set; }
    public int FramesSent { get; private set; }

    public void Start(
        string peerHost,
        ushort peerPort,
        string localPeerId,
        string remotePeerId,
        Func<Layout> layoutProvider,
        Func<IReadOnlyList<DisplayInfo>> remoteDisplaysProvider,
        string? kmSharedSecret)
    {
        lock (_gate)
        {
            if (IsRunning) return;

            PeerHost = peerHost.Trim();
            PeerPort = peerPort;
            KmAuthEnabled = !string.IsNullOrWhiteSpace(kmSharedSecret);
            FramesSent = 0;
            _heartbeatSeq = 1_000_000_000;
            _lastFrameSentAt = DateTime.MinValue;
            _lastStatsChangedUtc = DateTime.MinValue;

            _stream = new UdpKmStream(kmSharedSecret);
            _bridge = new WindowsEdgeBridge(localPeerId, remotePeerId, layoutProvider, remoteDisplaysProvider, _stream, PeerHost, PeerPort)
            {
                Log = Log
            };

            _hooks = new LowLevelHooks();
            _hooks.OnFrame += HandleFrame;
            try
            {
                _hooks.SuppressLocalEvents = _bridge.ShouldSuppressLocalEvents;
                _hooks.Start();

                // Heartbeat 50ms keeps the Mac receiver's link monitor up.
                _heartbeatTimer = new System.Threading.Timer(_ => HeartbeatTick(), null, TimeSpan.FromMilliseconds(50), TimeSpan.FromMilliseconds(50));

                _hotkey = new HotkeyManager();
                _hotkey.OnForceSwitch += HandleForceSwitch;
                if (!_hotkey.Register())
                    Log("Force-switch hotkey could not be registered (already in use?).");

                IsRunning = true;
                Log($"Sending KM frames to {PeerHost}:{PeerPort} using synced layout{(KmAuthEnabled ? " with HMAC authentication" : "")}.");
                NotifyStatsChanged(immediate: true);
            }
            catch
            {
                Stop();
                throw;
            }
        }
    }

    public void Stop()
    {
        lock (_gate)
        {
            var wasRunning = IsRunning;
            IsRunning = false;

            _heartbeatTimer?.Dispose();
            _heartbeatTimer = null;

            _hotkey?.Dispose();
            _hotkey = null;

            _hooks?.Stop();
            _hooks?.Dispose();
            _hooks = null;

            _bridge?.Stop();
            _bridge = null;

            _stream?.Close();
            _stream = null;

            if (wasRunning)
                Log("Sender stopped.");

            NotifyStatsChanged(immediate: true);
        }
    }

    public void Dispose() => Stop();

    private void HandleFrame(KmFrame frame)
    {
        var bridge = _bridge;
        var hooks = _hooks;
        if (bridge is null || hooks is null) return;

        var didSend = bridge.Handle(frame);
        hooks.SuppressLocalEvents = bridge.ShouldSuppressLocalEvents;
        if (!didSend) return;

        _lastFrameSentAt = DateTime.UtcNow;
        FramesSent++;
        if (FramesSent <= 3 || FramesSent % 500 == 0)
            Log($"sent seq={frame.Seq} type={frame.Type}");
        NotifyStatsChanged();
    }

    private void HandleForceSwitch()
    {
        var bridge = _bridge;
        var hooks = _hooks;
        if (bridge is null || hooks is null) return;
        bridge.ToggleRemote();
        hooks.SuppressLocalEvents = bridge.ShouldSuppressLocalEvents;
        Log($"Force-switch: {(bridge.ShouldSuppressLocalEvents ? "entered remote" : "back to Windows")}");
    }

    private void HeartbeatTick()
    {
        var bridge = _bridge;
        if (bridge is null) return;
        if ((DateTime.UtcNow - _lastFrameSentAt).TotalMilliseconds < 45)
            return;

        _heartbeatSeq = unchecked(_heartbeatSeq + 1);
        var frame = new KmFrame(
            _heartbeatSeq,
            (ulong)DateTimeOffset.UtcNow.ToUnixTimeMilliseconds() * 1000,
            KmType.Heartbeat);
        bridge.SendBypassingEdge(frame);
        _lastFrameSentAt = DateTime.UtcNow;
    }

    private void Log(string message)
    {
        LogLine?.Invoke($"[{DateTime.Now:HH:mm:ss}] {message}");
    }

    private void NotifyStatsChanged(bool immediate = false)
    {
        var now = DateTime.UtcNow;
        if (!immediate && now - _lastStatsChangedUtc < TimeSpan.FromMilliseconds(100))
            return;

        _lastStatsChangedUtc = now;
        StatsChanged?.Invoke();
    }
}
