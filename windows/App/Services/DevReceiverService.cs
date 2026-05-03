using System.Runtime.InteropServices;
using BarelyReal.Core.Clipboard;
using BarelyReal.Core.Km;
using BarelyReal.Core.Network;
using BarelyReal.Core.Protocol;

namespace BarelyReal.App.Services;

internal sealed class DevReceiverService : IDisposable
{
    private readonly object _gate = new();
    private readonly ClipboardHistory _history = new();
    private UdpKmStream? _stream;
    private InputInjector? _injector;
    private CancellationTokenSource? _cts;
    private Task? _clipboardTask;
    private KmLinkMonitor? _linkMonitor;

    public ClipboardHistory History => _history;
    public event Action? HistoryChanged;

    public event Action<string>? LogLine;
    public event Action? StatsChanged;

    public bool IsRunning { get; private set; }
    public bool LinkUp { get; private set; }
    public bool LockOnDisconnect { get; set; }
    public ushort KmPort { get; private set; }
    public ushort ClipboardPort { get; private set; }
    public string ClipboardPeer { get; private set; } = string.Empty;
    public int FramesReceived { get; private set; }
    public int ClipboardEvents { get; private set; }

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool LockWorkStation();

    public void Start(ushort kmPort, string clipboardPeer, ushort clipboardPort)
    {
        lock (_gate)
        {
            if (IsRunning)
                return;

            KmPort = kmPort;
            ClipboardPort = clipboardPort;
            ClipboardPeer = clipboardPeer.Trim();
            FramesReceived = 0;
            ClipboardEvents = 0;
            _cts = new CancellationTokenSource();
            _injector = new InputInjector();
            _stream = new UdpKmStream();
            _stream.OnFrame += HandleFrame;

            try
            {
                _stream.Bind(kmPort);

                _linkMonitor = new KmLinkMonitor();
                _linkMonitor.OnEvent += HandleLinkEvent;
                _linkMonitor.Start();

                StartClipboardIfNeeded(_cts.Token);
                IsRunning = true;
                Log($"Receiving KM frames on UDP :{kmPort}.");
                if (!string.IsNullOrWhiteSpace(ClipboardPeer))
                    Log($"Clipboard sync listening on TCP :{clipboardPort}, peer {ClipboardPeer}:{clipboardPort}.");
                StatsChanged?.Invoke();
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
            LinkUp = false;

            _cts?.Cancel();
            _stream?.Close();
            _linkMonitor?.Dispose();

            try
            {
                _clipboardTask?.Wait(TimeSpan.FromSeconds(1));
            }
            catch (AggregateException)
            {
            }

            _stream = null;
            _injector = null;
            _linkMonitor = null;
            _clipboardTask = null;
            _cts?.Dispose();
            _cts = null;

            if (wasRunning)
                Log("Receiver stopped.");

            StatsChanged?.Invoke();
        }
    }

    private void HandleLinkEvent(KmLinkMonitor.Event ev, TimeSpan silent)
    {
        switch (ev)
        {
            case KmLinkMonitor.Event.LinkRecovered:
                LinkUp = true;
                Log("KM link up.");
                StatsChanged?.Invoke();
                break;

            case KmLinkMonitor.Event.LinkLost:
                LinkUp = false;
                Log($"KM link lost (silent for {silent.TotalMilliseconds:F0} ms).");
                StatsChanged?.Invoke();
                break;

            case KmLinkMonitor.Event.ShouldLockScreen:
                if (LockOnDisconnect)
                {
                    Log($"Locking workstation (silent for {silent.TotalSeconds:F1} s).");
                    try { _ = LockWorkStation(); }
                    catch (Exception ex) { Log($"LockWorkStation failed: {ex.Message}"); }
                }
                break;
        }
    }

    public void Dispose()
    {
        Stop();
    }

    private void StartClipboardIfNeeded(CancellationToken token)
    {
        if (string.IsNullOrWhiteSpace(ClipboardPeer))
            return;

        var clipboard = new WindowsClipboardTextSync(ClipboardPeer, ClipboardPort, line =>
        {
            if (line.StartsWith("clipboard <-", StringComparison.OrdinalIgnoreCase)
                || line.StartsWith("clipboard ->", StringComparison.OrdinalIgnoreCase))
            {
                ClipboardEvents++;
                StatsChanged?.Invoke();
            }

            Log(line);
        });

        clipboard.OnHistoryEntry = entry =>
        {
            try
            {
                _history.Append(entry);
                HistoryChanged?.Invoke();
            }
            catch
            {
                // History writes are best-effort.
            }
        };

        _clipboardTask = Task.Run(async () =>
        {
            try
            {
                await clipboard.Run(token).ConfigureAwait(false);
            }
            catch (OperationCanceledException)
            {
            }
            catch (Exception ex)
            {
                Log($"Clipboard sync stopped: {ex.Message}");
            }
        }, token);
    }

    private void HandleFrame(KmFrame frame)
    {
        var injector = _injector;
        if (injector is null)
            return;

        // Heartbeats are flow-only; they keep the link monitor happy but produce no input.
        _linkMonitor?.NoteFrame();

        if (frame.Type == KmType.Heartbeat || frame.Type == KmType.ClockSync)
        {
            return;
        }

        try
        {
            injector.Inject(frame);
        }
        catch (Exception ex)
        {
            Log($"inject failed: {ex.Message}");
        }

        FramesReceived++;
        if (FramesReceived <= 10 || FramesReceived % 100 == 0)
            Log($"received seq={frame.Seq} type={frame.Type}");

        StatsChanged?.Invoke();
    }

    private void Log(string message)
    {
        LogLine?.Invoke($"[{DateTime.Now:HH:mm:ss}] {message}");
    }
}
