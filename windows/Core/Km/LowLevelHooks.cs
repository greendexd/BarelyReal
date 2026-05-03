using BarelyReal.Core.Protocol;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace BarelyReal.Core.Km;

/// Captures local mouse + keyboard via WH_MOUSE_LL and WH_KEYBOARD_LL hooks.
public sealed class LowLevelHooks : IDisposable
{
    public event Action<KmFrame>? OnFrame;
    public bool SuppressLocalEvents { get; set; }

    private HookProc? _mouseProc;
    private HookProc? _keyboardProc;
    private IntPtr _mouseHook;
    private IntPtr _keyboardHook;
    private Thread? _thread;
    private volatile bool _running;
    private uint _threadId;
    private uint _seq;
    private POINT? _lastMousePoint;
    private ManualResetEventSlim? _started;
    private Exception? _startError;

    public void Start()
    {
        if (_running)
            return;

        _startError = null;
        _started = new ManualResetEventSlim(false);
        _running = true;
        _thread = new Thread(MessagePump)
        {
            IsBackground = true,
            Name = "BarelyReal low-level hook pump"
        };
        _thread.SetApartmentState(ApartmentState.STA);
        _thread.Start();

        if (!_started.Wait(TimeSpan.FromSeconds(2)))
        {
            _running = false;
            throw new TimeoutException("Timed out starting low-level hook pump.");
        }

        if (_startError is not null)
        {
            var ex = _startError;
            _startError = null;
            throw new InvalidOperationException("Failed to start low-level hooks.", ex);
        }
    }

    public void Stop()
    {
        if (!_running)
            return;

        _running = false;
        if (_threadId != 0)
            _ = PostThreadMessage(_threadId, WM_QUIT, IntPtr.Zero, IntPtr.Zero);

        _thread?.Join(TimeSpan.FromSeconds(2));
        _thread = null;
    }

    public void Dispose()
    {
        Stop();
    }

    private void MessagePump()
    {
        _threadId = GetCurrentThreadId();
        _mouseProc = MouseCallback;
        _keyboardProc = KeyboardCallback;

        try
        {
            _mouseHook = SetWindowsHookEx(WH_MOUSE_LL, _mouseProc, IntPtr.Zero, 0);
            if (_mouseHook == IntPtr.Zero)
                throw new Win32Exception(Marshal.GetLastWin32Error(), "SetWindowsHookEx(WH_MOUSE_LL) failed.");

            _keyboardHook = SetWindowsHookEx(WH_KEYBOARD_LL, _keyboardProc, IntPtr.Zero, 0);
            if (_keyboardHook == IntPtr.Zero)
                throw new Win32Exception(Marshal.GetLastWin32Error(), "SetWindowsHookEx(WH_KEYBOARD_LL) failed.");

            _started?.Set();

            while (GetMessage(out var msg, IntPtr.Zero, 0, 0) > 0)
            {
                _ = TranslateMessage(ref msg);
                _ = DispatchMessage(ref msg);
            }
        }
        catch (Exception ex)
        {
            _startError = ex;
            _started?.Set();
        }
        finally
        {
            if (_mouseHook != IntPtr.Zero)
                _ = UnhookWindowsHookEx(_mouseHook);
            if (_keyboardHook != IntPtr.Zero)
                _ = UnhookWindowsHookEx(_keyboardHook);

            _mouseHook = IntPtr.Zero;
            _keyboardHook = IntPtr.Zero;
            _threadId = 0;
            _running = false;
        }
    }

    private IntPtr MouseCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0)
        {
            var hook = Marshal.PtrToStructure<MSLLHOOKSTRUCT>(lParam);
            if (SuppressLocalEvents && IsInjectedMouse(hook))
            {
                _lastMousePoint = hook.pt;
                return new IntPtr(1);
            }

            var frame = MouseFrame((int)wParam, hook);
            if (frame is not null)
                Emit(frame);

            if (SuppressLocalEvents)
                return new IntPtr(1);
        }

        return CallNextHookEx(_mouseHook, nCode, wParam, lParam);
    }

    private IntPtr KeyboardCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0)
        {
            var hook = Marshal.PtrToStructure<KBDLLHOOKSTRUCT>(lParam);
            if (SuppressLocalEvents && IsInjectedKeyboard(hook))
                return new IntPtr(1);

            var message = (int)wParam;
            var isDown = message is WM_KEYDOWN or WM_SYSKEYDOWN;
            var isUp = message is WM_KEYUP or WM_SYSKEYUP;

            if (isDown || isUp)
            {
                var keyCode = EncodeKeyboardScanCodeForWire(hook.scanCode, hook.flags);
                var payload = KmPayload.EncodeKey(new KmPayload.Key(keyCode, hook.flags));
                Emit(new KmFrame(NextSeq(), NowUs(), isDown ? KmType.KeyDown : KmType.KeyUp, payload));
            }

            if (SuppressLocalEvents)
                return new IntPtr(1);
        }

        return CallNextHookEx(_keyboardHook, nCode, wParam, lParam);
    }

    private KmFrame? MouseFrame(int message, MSLLHOOKSTRUCT hook)
    {
        switch (message)
        {
            case WM_MOUSEMOVE:
                if (_lastMousePoint is null)
                {
                    _lastMousePoint = hook.pt;
                    return new KmFrame(
                        NextSeq(),
                        NowUs(),
                        KmType.MouseMoveAbs,
                        KmPayload.EncodeMouseMove(new KmPayload.MouseMove(hook.pt.X, hook.pt.Y)));
                }

                var dx = hook.pt.X - _lastMousePoint.Value.X;
                var dy = hook.pt.Y - _lastMousePoint.Value.Y;
                _lastMousePoint = hook.pt;
                if (dx == 0 && dy == 0)
                    return null;

                return new KmFrame(
                    NextSeq(),
                    NowUs(),
                    KmType.MouseMoveRel,
                    KmPayload.EncodeMouseMove(new KmPayload.MouseMove(dx, dy)));

            case WM_LBUTTONDOWN:
            case WM_LBUTTONUP:
                return MouseButtonFrame(0, message == WM_LBUTTONDOWN);
            case WM_RBUTTONDOWN:
            case WM_RBUTTONUP:
                return MouseButtonFrame(1, message == WM_RBUTTONDOWN);
            case WM_MBUTTONDOWN:
            case WM_MBUTTONUP:
                return MouseButtonFrame(2, message == WM_MBUTTONDOWN);
            case WM_MOUSEWHEEL:
                return MouseScrollFrame(0, HighWordSigned(hook.mouseData));
            case WM_MOUSEHWHEEL:
                return MouseScrollFrame(HighWordSigned(hook.mouseData), 0);
            default:
                return null;
        }
    }

    private KmFrame MouseButtonFrame(byte button, bool isDown) =>
        new(NextSeq(), NowUs(), KmType.MouseButton, KmPayload.EncodeMouseButton(new KmPayload.MouseButton(button, isDown)));

    private KmFrame MouseScrollFrame(int deltaX, int deltaY) =>
        new(NextSeq(), NowUs(), KmType.MouseScroll, KmPayload.EncodeMouseScroll(new KmPayload.MouseScroll(deltaX, deltaY)));

    private uint NextSeq() => unchecked(_seq++);

    private void Emit(KmFrame frame)
    {
        try
        {
            OnFrame?.Invoke(frame);
        }
        catch
        {
            // Hook callbacks must not throw back into user32.
        }
    }

    private static ulong NowUs() =>
        (ulong)((DateTimeOffset.UtcNow.Ticks - DateTimeOffset.UnixEpoch.Ticks) / 10);

    private static int HighWordSigned(uint value) => unchecked((short)((value >> 16) & 0xFFFF));

    private static bool IsInjectedMouse(MSLLHOOKSTRUCT hook) => (hook.flags & LLMHF_INJECTED) != 0;
    private static bool IsInjectedKeyboard(KBDLLHOOKSTRUCT hook) => (hook.flags & LLKHF_INJECTED) != 0;

    public static ushort EncodeKeyboardScanCodeForWire(uint scanCode, uint flags)
    {
        var normalized = (ushort)Math.Min(scanCode, 0xFF);
        return (flags & LLKHF_EXTENDED) != 0
            ? (ushort)(ExtendedScanCodePrefix | normalized)
            : normalized;
    }

    private delegate IntPtr HookProc(int nCode, IntPtr wParam, IntPtr lParam);

    private const int WH_MOUSE_LL = 14;
    private const int WH_KEYBOARD_LL = 13;
    private const int WM_QUIT = 0x0012;
    private const int WM_KEYDOWN = 0x0100;
    private const int WM_KEYUP = 0x0101;
    private const int WM_SYSKEYDOWN = 0x0104;
    private const int WM_SYSKEYUP = 0x0105;
    private const uint LLMHF_INJECTED = 0x01;
    private const uint LLKHF_EXTENDED = 0x01;
    private const uint LLKHF_INJECTED = 0x10;
    private const ushort ExtendedScanCodePrefix = 0xE000;
    private const int WM_MOUSEMOVE = 0x0200;
    private const int WM_LBUTTONDOWN = 0x0201;
    private const int WM_LBUTTONUP = 0x0202;
    private const int WM_RBUTTONDOWN = 0x0204;
    private const int WM_RBUTTONUP = 0x0205;
    private const int WM_MBUTTONDOWN = 0x0207;
    private const int WM_MBUTTONUP = 0x0208;
    private const int WM_MOUSEWHEEL = 0x020A;
    private const int WM_MOUSEHWHEEL = 0x020E;

    [StructLayout(LayoutKind.Sequential)]
    private struct POINT
    {
        public int X;
        public int Y;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MSLLHOOKSTRUCT
    {
        public POINT pt;
        public uint mouseData;
        public uint flags;
        public uint time;
        public UIntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct KBDLLHOOKSTRUCT
    {
        public uint vkCode;
        public uint scanCode;
        public uint flags;
        public uint time;
        public UIntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MSG
    {
        public IntPtr hwnd;
        public uint message;
        public UIntPtr wParam;
        public IntPtr lParam;
        public uint time;
        public POINT pt;
        public uint lPrivate;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetWindowsHookEx(int idHook, HookProc lpfn, IntPtr hmod, uint dwThreadId);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UnhookWindowsHookEx(IntPtr hhk);

    [DllImport("user32.dll")]
    private static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern int GetMessage(out MSG lpMsg, IntPtr hWnd, uint wMsgFilterMin, uint wMsgFilterMax);

    [DllImport("user32.dll")]
    private static extern bool TranslateMessage(ref MSG lpMsg);

    [DllImport("user32.dll")]
    private static extern IntPtr DispatchMessage(ref MSG lpMsg);

    [DllImport("user32.dll")]
    private static extern bool PostThreadMessage(uint idThread, int msg, IntPtr wParam, IntPtr lParam);

    [DllImport("kernel32.dll")]
    private static extern uint GetCurrentThreadId();
}
