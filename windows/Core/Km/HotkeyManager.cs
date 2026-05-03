using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;

namespace BarelyReal.Core.Km;

/// Global hotkey via user32 RegisterHotKey on a hidden message-only window.
/// Default combo: Win + Ctrl + Shift + S (analogue of macOS ⌃⇧⌥⌘S).
public sealed class HotkeyManager : IDisposable
{
    public sealed class Combo
    {
        /// Win32 virtual-key code (e.g. 0x53 = 'S').
        public uint VirtualKey { get; }
        /// Bitmask of MOD_ALT (1) | MOD_CONTROL (2) | MOD_SHIFT (4) | MOD_WIN (8) | MOD_NOREPEAT (0x4000).
        public uint Modifiers { get; }

        public Combo(uint virtualKey, uint modifiers)
        {
            VirtualKey = virtualKey;
            Modifiers = modifiers | MOD_NOREPEAT;
        }

        public static readonly Combo DefaultForceSwitch = new(0x53,
            MOD_CONTROL | MOD_SHIFT | MOD_WIN);
    }

    public event Action? OnForceSwitch;

    private const int HotkeyId = 0x4252; // 'BR'
    private const uint MOD_ALT = 0x0001;
    private const uint MOD_CONTROL = 0x0002;
    private const uint MOD_SHIFT = 0x0004;
    private const uint MOD_WIN = 0x0008;
    private const uint MOD_NOREPEAT = 0x4000;
    private const int WM_HOTKEY = 0x0312;

    private HwndSource? _source;
    private bool _registered;

    public bool Register(Combo? combo = null)
    {
        Unregister();

        // We need a window handle; create a tiny invisible message-only window through HwndSource.
        var parameters = new HwndSourceParameters("BarelyReal.HotkeySink")
        {
            Width = 0,
            Height = 0,
            ParentWindow = new IntPtr(-3), // HWND_MESSAGE
        };
        _source = new HwndSource(parameters);
        _source.AddHook(WndProc);

        var c = combo ?? Combo.DefaultForceSwitch;
        _registered = RegisterHotKey(_source.Handle, HotkeyId, c.Modifiers, c.VirtualKey);
        return _registered;
    }

    public void Unregister()
    {
        if (_source is null) return;
        if (_registered)
        {
            try { UnregisterHotKey(_source.Handle, HotkeyId); }
            catch { /* ignore */ }
        }
        _source.RemoveHook(WndProc);
        _source.Dispose();
        _source = null;
        _registered = false;
    }

    public void Dispose() => Unregister();

    private IntPtr WndProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg == WM_HOTKEY && wParam.ToInt32() == HotkeyId)
        {
            handled = true;
            try { OnForceSwitch?.Invoke(); }
            catch { /* never let handler crash WndProc */ }
        }
        return IntPtr.Zero;
    }

    [DllImport("user32.dll")]
    private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

    [DllImport("user32.dll")]
    private static extern bool UnregisterHotKey(IntPtr hWnd, int id);
}
