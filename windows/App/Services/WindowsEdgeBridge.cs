using System.Runtime.InteropServices;
using BarelyReal.Core.Km;
using BarelyReal.Core.Network;
using BarelyReal.Core.Protocol;

namespace BarelyReal.App.Services;

/// Mirror of mac/App/Services/MacKmSession.swift::EdgeBridge.
/// Decides whether the local cursor is "in remote (Mac) mode" and forwards frames.
internal sealed class WindowsEdgeBridge
{
    public enum Direction
    {
        /// Mac is left of Windows: leaving via the left Windows edge enters Mac.
        Left,
        /// Mac is right of Windows: leaving via the right Windows edge enters Mac.
        Right
    }

    public sealed class PeerScreen
    {
        public int Width { get; }
        public int Height { get; }
        public PeerScreen(int width, int height) { Width = width; Height = height; }
    }

    public bool ShouldSuppressLocalEvents => _isRemoteActive;
    public Action<string>? Log;

    private readonly Direction _direction;
    private readonly PeerScreen _peerScreen;
    private readonly UdpKmStream _stream;
    private readonly string _peerHost;
    private readonly ushort _peerPort;
    private readonly RECT _desktopBounds;

    private bool _isRemoteActive;
    private int _remoteX;
    private POINT? _pinnedPoint;

    public WindowsEdgeBridge(Direction direction, PeerScreen peerScreen, UdpKmStream stream, string peerHost, ushort peerPort)
    {
        _direction = direction;
        _peerScreen = peerScreen;
        _stream = stream;
        _peerHost = peerHost;
        _peerPort = peerPort;
        _desktopBounds = GetDesktopBounds();
        _remoteX = direction == Direction.Left ? -24 : 24;
    }

    /// Returns true if the frame was forwarded to the peer.
    public bool Handle(KmFrame frame)
    {
        if (!_isRemoteActive)
        {
            if (!ShouldEnterRemote(frame)) return false;
            var entryFrame = EnterRemote(frame);
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

    /// Force-toggle remote/local mode (used by global hotkey).
    public void ToggleRemote()
    {
        if (_isRemoteActive)
        {
            ReturnLocal();
        }
        else
        {
            // Synthesize an entry seed so the peer side warps to a sensible position.
            var seed = new KmFrame(
                (uint)Random.Shared.Next(1, 1_000_000),
                (ulong)DateTimeOffset.UtcNow.ToUnixTimeMilliseconds() * 1000,
                KmType.MouseMoveRel,
                KmPayload.EncodeMouseMove(new KmPayload.MouseMove(0, 0))
            );
            var entry = EnterRemote(seed);
            _stream.Send(entry, _peerHost, _peerPort);
        }
    }

    public void Stop()
    {
        ReturnLocal();
    }

    private bool ShouldEnterRemote(KmFrame frame)
    {
        if (frame.Type != KmType.MouseMoveRel) return false;
        var move = SafeDecodeMove(frame);
        if (move is null) return false;

        if (!GetCursorPos(out var cursor)) return false;
        return _direction switch
        {
            Direction.Left  => move.Value.X < 0 && cursor.X <= _desktopBounds.Left + 2,
            Direction.Right => move.Value.X > 0 && cursor.X >= _desktopBounds.Right - 2,
            _ => false
        };
    }

    private bool ShouldReturnLocal(KmFrame frame)
    {
        if (frame.Type != KmType.MouseMoveRel) return false;
        var move = SafeDecodeMove(frame);
        if (move is null) return false;

        return _direction switch
        {
            Direction.Left  => move.Value.X > 0 && _remoteX + move.Value.X >= 0,
            Direction.Right => move.Value.X < 0 && _remoteX + move.Value.X <= 0,
            _ => false
        };
    }

    private void UpdateRemotePosition(KmFrame frame)
    {
        if (frame.Type != KmType.MouseMoveRel) return;
        var move = SafeDecodeMove(frame);
        if (move is null) return;

        switch (_direction)
        {
            case Direction.Left:  _remoteX = Math.Min(0, _remoteX + move.Value.X); break;
            case Direction.Right: _remoteX = Math.Max(0, _remoteX + move.Value.X); break;
        }
    }

    private KmFrame EnterRemote(KmFrame reference)
    {
        _isRemoteActive = true;
        _remoteX = _direction == Direction.Left ? -24 : 24;

        if (!GetCursorPos(out var cursor))
            cursor = new POINT { X = _desktopBounds.Left, Y = _desktopBounds.Top };

        _pinnedPoint = LocalPinPoint(cursor.Y);
        if (_pinnedPoint is { } pin) _ = SetCursorPos(pin.X, pin.Y);

        var entry = PeerEntryPoint(cursor.Y);
        Log?.Invoke($"Entered Mac at peer x={entry.X}, y={entry.Y}");
        return new KmFrame(
            reference.Seq,
            reference.TimestampUs,
            KmType.MouseMoveAbs,
            KmPayload.EncodeMouseMove(entry));
    }

    private void ReturnLocal()
    {
        if (!_isRemoteActive) return;
        _isRemoteActive = false;
        _pinnedPoint = null;

        var x = _direction == Direction.Left
            ? _desktopBounds.Left + 4
            : _desktopBounds.Right - 4;
        if (GetCursorPos(out var cursor))
            _ = SetCursorPos(x, cursor.Y);
        Log?.Invoke("Returned to Windows");
    }

    private void MaintainPin()
    {
        if (_pinnedPoint is { } pin)
            _ = SetCursorPos(pin.X, pin.Y);
    }

    private KmPayload.MouseMove PeerEntryPoint(int localY)
    {
        var maxX = Math.Max(_peerScreen.Width - 1, 0);
        var maxY = Math.Max(_peerScreen.Height - 1, 0);
        var x = _direction == Direction.Left ? maxX : 0;
        var height = _desktopBounds.Bottom - _desktopBounds.Top;
        var normalizedY = height > 0
            ? Math.Clamp((double)(localY - _desktopBounds.Top) / height, 0, 1)
            : 0.5;
        var y = (int)Math.Round(normalizedY * maxY);
        return new KmPayload.MouseMove(x, Math.Clamp(y, 0, maxY));
    }

    private POINT LocalPinPoint(int localY)
    {
        var x = _direction == Direction.Left ? _desktopBounds.Left + 1 : _desktopBounds.Right - 1;
        var clampedY = Math.Clamp(localY, _desktopBounds.Top, _desktopBounds.Bottom - 1);
        return new POINT { X = x, Y = clampedY };
    }

    private static KmPayload.MouseMove? SafeDecodeMove(KmFrame frame)
    {
        try { return KmPayload.DecodeMouseMove(frame.Payload); }
        catch { return null; }
    }

    private static RECT GetDesktopBounds()
    {
        // SM_XVIRTUALSCREEN/YVIRTUALSCREEN/CXVIRTUALSCREEN/CYVIRTUALSCREEN cover the whole virtual desktop.
        var x = GetSystemMetrics(SM_XVIRTUALSCREEN);
        var y = GetSystemMetrics(SM_YVIRTUALSCREEN);
        var w = GetSystemMetrics(SM_CXVIRTUALSCREEN);
        var h = GetSystemMetrics(SM_CYVIRTUALSCREEN);
        return new RECT { Left = x, Top = y, Right = x + w, Bottom = y + h };
    }

    private struct RECT { public int Left, Top, Right, Bottom; }

    [StructLayout(LayoutKind.Sequential)]
    private struct POINT { public int X; public int Y; }

    [DllImport("user32.dll")] private static extern bool GetCursorPos(out POINT lpPoint);
    [DllImport("user32.dll")] private static extern bool SetCursorPos(int X, int Y);
    [DllImport("user32.dll")] private static extern int GetSystemMetrics(int nIndex);

    private const int SM_XVIRTUALSCREEN = 76;
    private const int SM_YVIRTUALSCREEN = 77;
    private const int SM_CXVIRTUALSCREEN = 78;
    private const int SM_CYVIRTUALSCREEN = 79;
}
