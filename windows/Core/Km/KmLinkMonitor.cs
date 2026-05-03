namespace BarelyReal.Core.Km;

/// Tracks "are KM frames flowing" on the receive side. Mirrors mac KmLinkMonitor.swift.
public sealed class KmLinkMonitor : IDisposable
{
    public sealed class Configuration
    {
        public TimeSpan LinkLostAfter { get; set; } = TimeSpan.FromMilliseconds(1500);
        public TimeSpan LockScreenAfter { get; set; } = TimeSpan.FromMilliseconds(5000);
        public TimeSpan PollInterval { get; set; } = TimeSpan.FromMilliseconds(100);
    }

    public enum Event
    {
        LinkLost,
        LinkRecovered,
        ShouldLockScreen
    }

    public event Action<Event, TimeSpan>? OnEvent;

    public bool IsLinkUp { get; private set; }
    public bool IsActive { get; private set; }

    private readonly Configuration _configuration;
    private readonly object _gate = new();
    private DateTime? _lastFrameAt;
    private bool _lockTriggered;
    private System.Threading.Timer? _timer;

    public KmLinkMonitor(Configuration? configuration = null)
    {
        _configuration = configuration ?? new Configuration();
    }

    public void Start()
    {
        Stop();
        IsActive = true;
        _timer = new System.Threading.Timer(_ => Tick(), null, _configuration.PollInterval, _configuration.PollInterval);
    }

    public void Stop()
    {
        _timer?.Dispose();
        _timer = null;
        IsActive = false;
        IsLinkUp = false;
        lock (_gate)
        {
            _lastFrameAt = null;
            _lockTriggered = false;
        }
    }

    public void NoteFrame()
    {
        bool recovered = false;
        lock (_gate)
        {
            _lastFrameAt = DateTime.UtcNow;
            _lockTriggered = false;
            if (!IsLinkUp)
            {
                IsLinkUp = true;
                recovered = true;
            }
        }
        if (recovered)
            OnEvent?.Invoke(Event.LinkRecovered, TimeSpan.Zero);
    }

    public void Dispose() => Stop();

    private void Tick()
    {
        if (!IsActive) return;

        DateTime? lastFrameAt;
        bool lockTriggered;
        lock (_gate)
        {
            lastFrameAt = _lastFrameAt;
            lockTriggered = _lockTriggered;
        }

        if (lastFrameAt is null) return;

        var silent = DateTime.UtcNow - lastFrameAt.Value;

        if (IsLinkUp && silent >= _configuration.LinkLostAfter)
        {
            IsLinkUp = false;
            OnEvent?.Invoke(Event.LinkLost, silent);
        }

        if (!lockTriggered && silent >= _configuration.LockScreenAfter)
        {
            lock (_gate) { _lockTriggered = true; }
            OnEvent?.Invoke(Event.ShouldLockScreen, silent);
        }
    }
}
