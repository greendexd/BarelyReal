using System.Runtime.InteropServices;
using BarelyReal.Core.Km;
using BarelyReal.Core.Layout;
using BarelyReal.Core.Network;
using BarelyReal.Core.Protocol;

namespace BarelyReal.App.Services;

/// Layout-aware edge bridge for Windows -> Mac KM sharing.
internal sealed class WindowsEdgeBridge
{
    public bool ShouldSuppressLocalEvents => _isRemoteActive;
    public Action<string>? Log;

    private readonly string _localPeerId;
    private readonly string _remotePeerId;
    private readonly Func<Layout> _layoutProvider;
    private readonly Func<IReadOnlyList<DisplayInfo>> _remoteDisplaysProvider;
    private readonly UdpKmStream _stream;
    private readonly string _peerHost;
    private readonly ushort _peerPort;

    private bool _isRemoteActive;
    private POINT? _remoteVirtualPoint;
    private POINT? _pinnedPoint;
    private readonly RemoteInputGuard _guard = new();

    public WindowsEdgeBridge(
        string localPeerId,
        string remotePeerId,
        Func<Layout> layoutProvider,
        Func<IReadOnlyList<DisplayInfo>> remoteDisplaysProvider,
        UdpKmStream stream,
        string peerHost,
        ushort peerPort)
    {
        _localPeerId = localPeerId;
        _remotePeerId = remotePeerId;
        _layoutProvider = layoutProvider;
        _remoteDisplaysProvider = remoteDisplaysProvider;
        _stream = stream;
        _peerHost = peerHost;
        _peerPort = peerPort;
    }

    public bool Handle(KmFrame frame)
    {
        if (!_isRemoteActive)
        {
            var entryFrame = EntryFrameIfCrossing(frame);
            if (entryFrame is null) return false;
            _stream.Send(entryFrame, _peerHost, _peerPort);
            return true;
        }

        if (ShouldReturnLocal(frame))
        {
            ReturnLocal();
            return false;
        }

        UpdateRemotePosition(frame);
        MaintainPin();
        _stream.Send(frame, _peerHost, _peerPort);
        return true;
    }

    public void SendBypassingEdge(KmFrame frame) => _stream.Send(frame, _peerHost, _peerPort);

    public void ToggleRemote()
    {
        if (_isRemoteActive)
        {
            ReturnLocal();
            return;
        }

        var remote = _layoutProvider().ScreensFor(_remotePeerId).FirstOrDefault();
        if (remote is null)
        {
            Log?.Invoke("No remote screen in layout");
            return;
        }

        var target = new POINT { X = remote.X + remote.Width / 2, Y = remote.Y + remote.Height / 2 };
        var seed = new KmFrame(
            (uint)Random.Shared.Next(1, 1_000_000),
            (ulong)DateTimeOffset.UtcNow.ToUnixTimeMilliseconds() * 1000,
            KmType.MouseMoveRel,
            KmPayload.EncodeMouseMove(new KmPayload.MouseMove(0, 0)));
        var entry = EnterRemote(target, seed);
        if (entry is not null) _stream.Send(entry, _peerHost, _peerPort);
    }

    public void Stop() => ReturnLocal();

    private KmFrame? EntryFrameIfCrossing(KmFrame frame)
    {
        if (frame.Type != KmType.MouseMoveRel) return null;
        var move = SafeDecodeMove(frame);
        if (move is null) return null;
        if (!GetCursorPos(out var cursor)) return null;

        var projected = new POINT { X = cursor.X + move.Value.X, Y = cursor.Y + move.Value.Y };
        var layout = _layoutProvider();
        var currentScreen = layout.Screen(cursor.X, cursor.Y);
        var target = layout.Screen(projected.X, projected.Y);
        if (currentScreen?.PeerId != _localPeerId || target?.PeerId != _remotePeerId) return null;

        return EnterRemote(EntryPoint(projected, target, move.Value), frame);
    }

    private KmFrame? EnterRemote(POINT virtualPoint, KmFrame reference)
    {
        var layout = _layoutProvider();
        var target = layout.Screen(virtualPoint.X, virtualPoint.Y);
        if (target?.PeerId != _remotePeerId) return null;

        _isRemoteActive = true;
        _remoteVirtualPoint = virtualPoint;
        if (GetCursorPos(out var cursor))
        {
            _pinnedPoint = cursor;
            _guard.Start();
            _ = SetCursorPos(cursor.X, cursor.Y);
        }

        var native = RemoteNativePoint(virtualPoint, target);
        Log?.Invoke($"Entered Mac screen {target.ScreenId} at peer x={native.X}, y={native.Y}");
        return new KmFrame(
            reference.Seq,
            reference.TimestampUs,
            KmType.MouseMoveAbs,
            KmPayload.EncodeMouseMove(new KmPayload.MouseMove(native.X, native.Y)));
    }

    private bool ShouldReturnLocal(KmFrame frame)
    {
        if (frame.Type != KmType.MouseMoveRel || _remoteVirtualPoint is null) return false;
        var move = SafeDecodeMove(frame);
        if (move is null) return false;
        var projected = new POINT { X = _remoteVirtualPoint.Value.X + move.Value.X, Y = _remoteVirtualPoint.Value.Y + move.Value.Y };
        if (_layoutProvider().Screen(projected.X, projected.Y)?.PeerId == _localPeerId)
        {
            _pinnedPoint = projected;
            return true;
        }
        return false;
    }

    private void UpdateRemotePosition(KmFrame frame)
    {
        if (frame.Type != KmType.MouseMoveRel || _remoteVirtualPoint is null) return;
        var move = SafeDecodeMove(frame);
        if (move is null) return;
        _remoteVirtualPoint = new POINT { X = _remoteVirtualPoint.Value.X + move.Value.X, Y = _remoteVirtualPoint.Value.Y + move.Value.Y };
    }

    private void ReturnLocal()
    {
        if (!_isRemoteActive) return;
        _isRemoteActive = false;
        _guard.Stop();
        if (_pinnedPoint is { } point)
            _ = SetCursorPos(point.X, point.Y);
        _remoteVirtualPoint = null;
        _pinnedPoint = null;
        Log?.Invoke("Returned to Windows");
    }

    private void MaintainPin()
    {
        _guard.MaintainHidden();
        if (_pinnedPoint is { } pin)
            _ = SetCursorPos(pin.X, pin.Y);
    }

    private POINT RemoteNativePoint(POINT virtualPoint, ScreenRect layoutScreen)
    {
        var native = _remoteDisplaysProvider().FirstOrDefault(display => display.ScreenId == layoutScreen.ScreenId);
        if (native is not null)
        {
            return new POINT
            {
                X = native.X + (virtualPoint.X - layoutScreen.X),
                Y = native.Y + (virtualPoint.Y - layoutScreen.Y)
            };
        }
        return new POINT { X = virtualPoint.X - layoutScreen.X, Y = virtualPoint.Y - layoutScreen.Y };
    }

    private static KmPayload.MouseMove? SafeDecodeMove(KmFrame frame)
    {
        try { return KmPayload.DecodeMouseMove(frame.Payload); }
        catch { return null; }
    }

    private static POINT EntryPoint(POINT projected, ScreenRect target, KmPayload.MouseMove move)
    {
        var point = new POINT
        {
            X = Math.Clamp(projected.X, target.X, target.MaxX - 1),
            Y = Math.Clamp(projected.Y, target.Y, target.MaxY - 1)
        };

        if (Math.Abs(move.X) >= Math.Abs(move.Y) && move.X != 0)
            point.X = move.X > 0 ? target.X + EdgeEntryInset : target.MaxX - 1 - EdgeEntryInset;
        else if (move.Y != 0)
            point.Y = move.Y > 0 ? target.Y + EdgeEntryInset : target.MaxY - 1 - EdgeEntryInset;

        point.X = Math.Clamp(point.X, target.X, target.MaxX - 1);
        point.Y = Math.Clamp(point.Y, target.Y, target.MaxY - 1);
        return point;
    }

    private sealed class RemoteInputGuard
    {
        private bool _active;
        private int _hideCalls;

        public void Start()
        {
            if (_active) return;
            _hideCalls = HideCursor();
            _active = true;
        }

        public void MaintainHidden()
        {
            // Deliberately no-op: repeatedly calling ShowCursor(false) would drive
            // Windows' display counter far negative and make restoration unreliable.
        }

        public void Stop()
        {
            if (!_active) return;
            ShowCursorUntilVisible(_hideCalls);
            _hideCalls = 0;
            _active = false;
        }

        private static int HideCursor()
        {
            var calls = 0;
            for (var i = 0; i < 8; i++)
            {
                calls++;
                if (ShowCursor(false) < 0)
                    break;
            }
            return calls;
        }

        private static void ShowCursorUntilVisible(int hideCalls)
        {
            for (var i = 0; i < hideCalls; i++)
                _ = ShowCursor(true);
        }
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct POINT { public int X; public int Y; }

    [DllImport("user32.dll")] private static extern bool GetCursorPos(out POINT lpPoint);
    [DllImport("user32.dll")] private static extern bool SetCursorPos(int X, int Y);
    [DllImport("user32.dll")] private static extern int ShowCursor(bool bShow);

    private const int EdgeEntryInset = 24;
}
