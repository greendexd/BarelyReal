namespace BarelyReal.Core.Km;

/// HID Usage IDs (USB HID Usage Tables, Page 0x07) ↔ Windows scan code set 1.
///
/// These tables are the canonical wire format for BRP per the spec. The current scaffold still
/// ships native scan codes on the wire; this is the hand-off point when both sides switch.
public static class HidKeyMap
{
    public static ushort? HidForScanCode(ushort scanCode)
    {
        return ScanToHid.TryGetValue(scanCode, out var hid) ? hid : null;
    }

    public static ushort? ScanCodeForHid(ushort hid)
    {
        return HidToScan.TryGetValue(hid, out var scan) ? scan : null;
    }

    [Flags]
    public enum Modifiers : ushort
    {
        None = 0,
        LeftShift   = 0x0001,
        RightShift  = 0x0002,
        LeftCtrl    = 0x0004,
        RightCtrl   = 0x0008,
        LeftAlt     = 0x0010,
        RightAlt    = 0x0020,
        LeftGui     = 0x0040,
        RightGui    = 0x0080,
        CapsLock    = 0x0100,
        NumLock     = 0x0200,
        ScrollLock  = 0x0400,
    }

    /// Build a canonical BRP modifier bitmask from `GetKeyState` polling.
    /// Pass the deltas as the WinUser virtual-key codes; helper uses GetKeyState to read live state.
    public static Modifiers CurrentModifiers()
    {
        var mods = Modifiers.None;
        if ((GetKeyState(VK_LSHIFT)   & 0x8000) != 0) mods |= Modifiers.LeftShift;
        if ((GetKeyState(VK_RSHIFT)   & 0x8000) != 0) mods |= Modifiers.RightShift;
        if ((GetKeyState(VK_LCONTROL) & 0x8000) != 0) mods |= Modifiers.LeftCtrl;
        if ((GetKeyState(VK_RCONTROL) & 0x8000) != 0) mods |= Modifiers.RightCtrl;
        if ((GetKeyState(VK_LMENU)    & 0x8000) != 0) mods |= Modifiers.LeftAlt;
        if ((GetKeyState(VK_RMENU)    & 0x8000) != 0) mods |= Modifiers.RightAlt;
        if ((GetKeyState(VK_LWIN)     & 0x8000) != 0) mods |= Modifiers.LeftGui;
        if ((GetKeyState(VK_RWIN)     & 0x8000) != 0) mods |= Modifiers.RightGui;
        if ((GetKeyState(VK_CAPITAL)  & 0x0001) != 0) mods |= Modifiers.CapsLock;
        if ((GetKeyState(VK_NUMLOCK)  & 0x0001) != 0) mods |= Modifiers.NumLock;
        if ((GetKeyState(VK_SCROLL)   & 0x0001) != 0) mods |= Modifiers.ScrollLock;
        return mods;
    }

    [System.Runtime.InteropServices.DllImport("user32.dll")]
    private static extern short GetKeyState(int nVirtKey);

    private const int VK_LSHIFT = 0xA0;
    private const int VK_RSHIFT = 0xA1;
    private const int VK_LCONTROL = 0xA2;
    private const int VK_RCONTROL = 0xA3;
    private const int VK_LMENU = 0xA4;
    private const int VK_RMENU = 0xA5;
    private const int VK_LWIN = 0x5B;
    private const int VK_RWIN = 0x5C;
    private const int VK_CAPITAL = 0x14;
    private const int VK_NUMLOCK = 0x90;
    private const int VK_SCROLL = 0x91;

    /// Windows scan code set 1 → HID Usage Page 0x07.
    /// Mirrors mac/Core/KM/HidKeyMap.swift with values transposed via the standard PS/2 ↔ HID table.
    private static readonly Dictionary<ushort, ushort> ScanToHid = new()
    {
        // Top alpha row
        { 0x10, 0x14 }, { 0x11, 0x1A }, { 0x12, 0x08 }, { 0x13, 0x15 }, { 0x14, 0x17 },
        { 0x15, 0x1C }, { 0x16, 0x18 }, { 0x17, 0x0C }, { 0x18, 0x12 }, { 0x19, 0x13 },
        // Home row
        { 0x1E, 0x04 }, { 0x1F, 0x16 }, { 0x20, 0x07 }, { 0x21, 0x09 }, { 0x22, 0x0A },
        { 0x23, 0x0B }, { 0x24, 0x0D }, { 0x25, 0x0E }, { 0x26, 0x0F }, { 0x27, 0x33 },
        { 0x28, 0x34 }, { 0x29, 0x35 },
        // Bottom alpha row
        { 0x2C, 0x1D }, { 0x2D, 0x1B }, { 0x2E, 0x06 }, { 0x2F, 0x19 }, { 0x30, 0x05 },
        { 0x31, 0x11 }, { 0x32, 0x10 }, { 0x33, 0x36 }, { 0x34, 0x37 }, { 0x35, 0x38 },
        // Digits row
        { 0x02, 0x1E }, { 0x03, 0x1F }, { 0x04, 0x20 }, { 0x05, 0x21 }, { 0x06, 0x22 },
        { 0x07, 0x23 }, { 0x08, 0x24 }, { 0x09, 0x25 }, { 0x0A, 0x26 }, { 0x0B, 0x27 },
        { 0x0C, 0x2D }, { 0x0D, 0x2E },
        // Misc
        { 0x01, 0x29 }, // Esc
        { 0x0E, 0x2A }, // Backspace
        { 0x0F, 0x2B }, // Tab
        { 0x1A, 0x2F }, // [
        { 0x1B, 0x30 }, // ]
        { 0x1C, 0x28 }, // Enter
        { 0x2B, 0x31 }, // Backslash
        { 0x39, 0x2C }, // Space
        { 0x3A, 0x39 }, // CapsLock
        // Function keys
        { 0x3B, 0x3A }, { 0x3C, 0x3B }, { 0x3D, 0x3C }, { 0x3E, 0x3D }, { 0x3F, 0x3E },
        { 0x40, 0x3F }, { 0x41, 0x40 }, { 0x42, 0x41 }, { 0x43, 0x42 }, { 0x44, 0x43 },
        { 0x57, 0x44 }, { 0x58, 0x45 },
        { 0xE037, 0x46 }, // Print Screen
        { 0x46, 0x47 },   // Scroll Lock
        { 0x45, 0x48 },   // Pause/Break best-effort in current scan-code mode
        // Navigation cluster (extended scancodes)
        { 0xE052, 0x49 }, { 0xE047, 0x4A }, { 0xE049, 0x4B }, { 0xE053, 0x4C },
        { 0xE04F, 0x4D }, { 0xE051, 0x4E },
        { 0xE04D, 0x4F }, { 0xE04B, 0x50 }, { 0xE050, 0x51 }, { 0xE048, 0x52 },
        // Modifiers
        { 0x1D, 0xE0 }, // LCtrl
        { 0x2A, 0xE1 }, // LShift
        { 0x38, 0xE2 }, // LAlt
        { 0xE05B, 0xE3 }, // LWin
        { 0xE01D, 0xE4 }, // RCtrl
        { 0x36, 0xE5 }, // RShift (in scancode set 1)
        { 0xE038, 0xE6 }, // RAlt
        { 0xE05C, 0xE7 }, // RWin
    };

    private static readonly Dictionary<ushort, ushort> HidToScan = BuildReverse(ScanToHid);

    private static Dictionary<ushort, ushort> BuildReverse(Dictionary<ushort, ushort> source)
    {
        var dict = new Dictionary<ushort, ushort>(source.Count);
        foreach (var kv in source)
        {
            // First wins on duplicates.
            dict.TryAdd(kv.Value, kv.Key);
        }
        return dict;
    }
}
