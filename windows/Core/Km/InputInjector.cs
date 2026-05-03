using BarelyReal.Core.Protocol;
using System.Runtime.InteropServices;

namespace BarelyReal.Core.Km;

/// Injects mouse + keyboard events received from the peer via SendInput.
/// Applies the modifier remap table (Cmd↔Ctrl, Option↔Alt) before posting.
public sealed class InputInjector
{
    public readonly record struct KeyInjection(ushort ScanCode, bool IsExtended);

    public sealed class ModifierRemap
    {
        public bool CmdToCtrl { get; set; } = true;
        public bool OptionToAlt { get; set; } = true;
    }

    public ModifierRemap Remap { get; } = new();
    public bool AssumeMacVirtualKeyCodes { get; set; } = true;
    public Action<string>? Log { get; set; }

    public void Inject(KmFrame frame)
    {
        switch (frame.Type)
        {
            case KmType.MouseMoveRel:
                var rel = KmPayload.DecodeMouseMove(frame.Payload);
                SendMouse(rel.X, rel.Y, 0, MOUSEEVENTF_MOVE);
                break;

            case KmType.MouseMoveAbs:
                var abs = KmPayload.DecodeMouseMove(frame.Payload);
                if (!SetCursorPos(abs.X, abs.Y))
                {
                    Log?.Invoke($"SetCursorPos failed x={abs.X} y={abs.Y} error={Marshal.GetLastWin32Error()}");
                }
                break;

            case KmType.MouseButton:
                var button = KmPayload.DecodeMouseButton(frame.Payload);
                SendMouseButton(button);
                break;

            case KmType.MouseScroll:
                var scroll = KmPayload.DecodeMouseScroll(frame.Payload);
                if (scroll.DeltaY != 0)
                    SendMouse(0, 0, scroll.DeltaY, MOUSEEVENTF_WHEEL);
                if (scroll.DeltaX != 0)
                    SendMouse(0, 0, scroll.DeltaX, MOUSEEVENTF_HWHEEL);
                break;

            case KmType.KeyDown:
                SendKey(KmPayload.DecodeKey(frame.Payload), isDown: true);
                break;

            case KmType.KeyUp:
                SendKey(KmPayload.DecodeKey(frame.Payload), isDown: false);
                break;

            case KmType.ModifiersChanged:
                _ = KmPayload.DecodeModifiers(frame.Payload);
                break;

            case KmType.Heartbeat:
            case KmType.ClockSync:
                break;
        }
    }

    private void SendMouseButton(KmPayload.MouseButton button)
    {
        uint flags = button switch
        {
            { Button: 0, IsDown: true } => MOUSEEVENTF_LEFTDOWN,
            { Button: 0, IsDown: false } => MOUSEEVENTF_LEFTUP,
            { Button: 1, IsDown: true } => MOUSEEVENTF_RIGHTDOWN,
            { Button: 1, IsDown: false } => MOUSEEVENTF_RIGHTUP,
            { Button: 2, IsDown: true } => MOUSEEVENTF_MIDDLEDOWN,
            { Button: 2, IsDown: false } => MOUSEEVENTF_MIDDLEUP,
            _ => 0u
        };

        if (flags != 0)
            SendMouse(0, 0, 0, flags);
    }

    private void SendMouse(int dx, int dy, int mouseData, uint flags)
    {
        var input = new INPUT
        {
            type = INPUT_MOUSE,
            U = new InputUnion
            {
                mi = new MOUSEINPUT
                {
                    dx = dx,
                    dy = dy,
                    mouseData = mouseData,
                    dwFlags = flags
                }
            }
        };

        Send(input);
    }

    private void SendKey(KmPayload.Key key, bool isDown)
    {
        var mapped = TranslateKeyForInjection(key.KeyCode);
        var flags = KEYEVENTF_SCANCODE | (isDown ? 0 : KEYEVENTF_KEYUP);
        if (mapped.IsExtended)
            flags |= KEYEVENTF_EXTENDEDKEY;

        var input = new INPUT
        {
            type = INPUT_KEYBOARD,
            U = new InputUnion
            {
                ki = new KEYBDINPUT
                {
                    wScan = mapped.ScanCode,
                    dwFlags = flags
                }
            }
        };

        Send(input);
    }

    public KeyInjection TranslateKeyForInjection(ushort keyCode)
    {
        if (AssumeMacVirtualKeyCodes && !IsExtendedScanCode(keyCode))
        {
            if (Remap.CmdToCtrl && (keyCode == MacLeftCommand || keyCode == MacRightCommand))
                return new KeyInjection(WindowsLeftControl, IsExtended: false);

            if (Remap.OptionToAlt && (keyCode == MacLeftOption || keyCode == MacRightOption))
                return new KeyInjection(WindowsLeftAlt, IsExtended: false);
        }

        var scanCode = NormalizeScanCode(keyCode);

        return new KeyInjection(BaseScanCode(scanCode), IsExtendedScanCode(scanCode));
    }

    private ushort NormalizeScanCode(ushort keyCode)
    {
        if (IsExtendedScanCode(keyCode))
            return keyCode;

        if (!AssumeMacVirtualKeyCodes)
            return keyCode;

        return MacVirtualKeyToWindowsScanCode(keyCode) ?? keyCode;
    }

    private static ushort? MacVirtualKeyToWindowsScanCode(ushort keyCode) =>
        keyCode switch
        {
            0x00 => 0x1E, // A
            0x01 => 0x1F, // S
            0x02 => 0x20, // D
            0x03 => 0x21, // F
            0x04 => 0x23, // H
            0x05 => 0x22, // G
            0x06 => 0x2C, // Z
            0x07 => 0x2D, // X
            0x08 => 0x2E, // C
            0x09 => 0x2F, // V
            0x0B => 0x30, // B
            0x0C => 0x10, // Q
            0x0D => 0x11, // W
            0x0E => 0x12, // E
            0x0F => 0x13, // R
            0x10 => 0x15, // Y
            0x11 => 0x14, // T
            0x12 => 0x02, // 1
            0x13 => 0x03, // 2
            0x14 => 0x04, // 3
            0x15 => 0x05, // 4
            0x16 => 0x07, // 6
            0x17 => 0x06, // 5
            0x18 => 0x0D, // =
            0x19 => 0x0A, // 9
            0x1A => 0x08, // 7
            0x1B => 0x0C, // -
            0x1C => 0x0B, // 0
            0x1D => 0x09, // 8
            0x1E => 0x1B, // ]
            0x1F => 0x18, // O
            0x20 => 0x16, // U
            0x21 => 0x1A, // [
            0x22 => 0x17, // I
            0x23 => 0x19, // P
            0x24 => 0x1C, // Return
            0x25 => 0x26, // L
            0x26 => 0x24, // J
            0x27 => 0x28, // '
            0x28 => 0x25, // K
            0x29 => 0x27, // ;
            0x2A => 0x2B, // \
            0x2B => 0x33, // ,
            0x2C => 0x35, // /
            0x2D => 0x31, // N
            0x2E => 0x32, // M
            0x2F => 0x34, // .
            0x30 => 0x0F, // Tab
            0x31 => 0x39, // Space
            0x32 => 0x29, // `
            0x33 => 0x0E, // Backspace
            0x35 => 0x01, // Escape
            0x36 => Extended(0x5C), // Right Command -> Right Windows key if remap is disabled
            0x37 => Extended(0x5B), // Command -> Left Windows key if remap is disabled
            0x38 => 0x2A, // Left Shift
            0x39 => 0x3A, // Caps Lock
            0x3A => WindowsLeftAlt,
            0x3B => WindowsLeftControl,
            0x3C => 0x36, // Right Shift
            0x3D => Extended(0x38), // Right Option / Alt
            0x3E => Extended(0x1D), // Right Control
            0x41 => 0x53, // Keypad decimal
            0x43 => 0x37, // Keypad *
            0x45 => 0x4E, // Keypad +
            0x47 => 0x45, // Keypad clear / Num Lock
            0x4B => Extended(0x35), // Keypad /
            0x4C => Extended(0x1C), // Keypad enter
            0x4E => 0x4A, // Keypad -
            0x52 => 0x52, // Keypad 0
            0x53 => 0x4F, // Keypad 1
            0x54 => 0x50, // Keypad 2
            0x55 => 0x51, // Keypad 3
            0x56 => 0x4B, // Keypad 4
            0x57 => 0x4C, // Keypad 5
            0x58 => 0x4D, // Keypad 6
            0x59 => 0x47, // Keypad 7
            0x5B => 0x48, // Keypad 8
            0x5C => 0x49, // Keypad 9
            0x60 => 0x3F, // F5
            0x61 => 0x40, // F6
            0x62 => 0x41, // F7
            0x63 => 0x3D, // F3
            0x64 => 0x42, // F8
            0x65 => 0x43, // F9
            0x67 => 0x57, // F11
            0x69 => Extended(0x37), // F13 / Print Screen on PC keyboards
            0x6B => 0x46, // F14 / Scroll Lock
            0x6D => 0x44, // F10
            0x6F => 0x58, // F12
            0x71 => 0x45, // F15 / Pause-Break best-effort in scancode dev mode
            0x72 => Extended(0x52), // Help / Insert
            0x73 => Extended(0x47), // Home
            0x74 => Extended(0x49), // Page Up
            0x75 => Extended(0x53), // Forward Delete
            0x76 => 0x3E, // F4
            0x77 => Extended(0x4F), // End
            0x78 => 0x3C, // F2
            0x79 => Extended(0x51), // Page Down
            0x7A => 0x3B, // F1
            0x7B => Extended(0x4B), // Left
            0x7C => Extended(0x4D), // Right
            0x7D => Extended(0x50), // Down
            0x7E => Extended(0x48), // Up
            _ => null
        };

    private static ushort Extended(ushort scanCode) => (ushort)(ExtendedScanCodePrefix | scanCode);
    private static ushort BaseScanCode(ushort scanCode) => (ushort)(scanCode & 0x00FF);
    private static bool IsExtendedScanCode(ushort scanCode) => (scanCode & ExtendedScanCodePrefix) == ExtendedScanCodePrefix;

    private void Send(INPUT input)
    {
        var inputs = new[] { input };
        var sent = SendInput(1, inputs, Marshal.SizeOf<INPUT>());
        if (sent != 1)
        {
            Log?.Invoke($"SendInput failed type={input.type} sent={sent} error={Marshal.GetLastWin32Error()}");
        }
    }

    private const uint INPUT_MOUSE = 0;
    private const uint INPUT_KEYBOARD = 1;
    private const uint MOUSEEVENTF_MOVE = 0x0001;
    private const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
    private const uint MOUSEEVENTF_LEFTUP = 0x0004;
    private const uint MOUSEEVENTF_RIGHTDOWN = 0x0008;
    private const uint MOUSEEVENTF_RIGHTUP = 0x0010;
    private const uint MOUSEEVENTF_MIDDLEDOWN = 0x0020;
    private const uint MOUSEEVENTF_MIDDLEUP = 0x0040;
    private const uint MOUSEEVENTF_WHEEL = 0x0800;
    private const uint MOUSEEVENTF_HWHEEL = 0x01000;
    private const uint KEYEVENTF_KEYUP = 0x0002;
    private const uint KEYEVENTF_EXTENDEDKEY = 0x0001;
    private const uint KEYEVENTF_SCANCODE = 0x0008;
    private const ushort MacLeftCommand = 0x37;
    private const ushort MacRightCommand = 0x36;
    private const ushort MacLeftOption = 0x3A;
    private const ushort MacRightOption = 0x3D;
    private const ushort WindowsLeftControl = 0x1D;
    private const ushort WindowsLeftAlt = 0x38;
    private const ushort ExtendedScanCodePrefix = 0xE000;

    [StructLayout(LayoutKind.Sequential)]
    private struct INPUT
    {
        public uint type;
        public InputUnion U;
    }

    [StructLayout(LayoutKind.Explicit)]
    private struct InputUnion
    {
        [FieldOffset(0)] public MOUSEINPUT mi;
        [FieldOffset(0)] public KEYBDINPUT ki;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MOUSEINPUT
    {
        public int dx;
        public int dy;
        public int mouseData;
        public uint dwFlags;
        public uint time;
        public UIntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct KEYBDINPUT
    {
        public ushort wVk;
        public ushort wScan;
        public uint dwFlags;
        public uint time;
        public UIntPtr dwExtraInfo;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool SetCursorPos(int x, int y);
}
