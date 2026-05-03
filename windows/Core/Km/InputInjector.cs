using BarelyReal.Core.Protocol;
using System.Runtime.InteropServices;

namespace BarelyReal.Core.Km;

/// Injects mouse + keyboard events received from the peer via SendInput.
/// Applies the modifier remap table (Cmd↔Ctrl, Option↔Alt) before posting.
public sealed class InputInjector
{
    public sealed class ModifierRemap
    {
        public bool CmdToCtrl { get; set; } = true;
        public bool OptionToAlt { get; set; } = true;
    }

    public ModifierRemap Remap { get; } = new();
    public bool AssumeMacVirtualKeyCodes { get; set; } = true;

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
                _ = SetCursorPos(abs.X, abs.Y);
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
        var scanCode = RemapScanCode(key.KeyCode);
        var flags = KEYEVENTF_SCANCODE | (isDown ? 0 : KEYEVENTF_KEYUP);
        if (IsExtendedKey(key.KeyCode, scanCode))
            flags |= KEYEVENTF_EXTENDEDKEY;

        var input = new INPUT
        {
            type = INPUT_KEYBOARD,
            U = new InputUnion
            {
                ki = new KEYBDINPUT
                {
                    wScan = scanCode,
                    dwFlags = flags
                }
            }
        };

        Send(input);
    }

    private ushort RemapScanCode(ushort scanCode)
    {
        scanCode = NormalizeScanCode(scanCode);

        if (Remap.CmdToCtrl && (scanCode == MacLeftCommand || scanCode == MacRightCommand))
            return WindowsLeftControl;

        if (Remap.OptionToAlt && (scanCode == MacLeftOption || scanCode == MacRightOption))
            return WindowsLeftAlt;

        return scanCode;
    }

    private ushort NormalizeScanCode(ushort keyCode)
    {
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
            0x36 => WindowsLeftControl, // Right Command -> Ctrl
            0x37 => WindowsLeftControl, // Command -> Ctrl
            0x38 => 0x2A, // Left Shift
            0x39 => 0x3A, // Caps Lock
            0x3A => WindowsLeftAlt,
            0x3B => WindowsLeftControl,
            0x3C => 0x36, // Right Shift
            0x3D => WindowsLeftAlt,
            0x3E => 0x1D, // Right Control
            0x73 => 0x47, // Home
            0x74 => 0x49, // Page Up
            0x75 => 0x53, // Forward Delete
            0x77 => 0x4F, // End
            0x79 => 0x51, // Page Down
            0x7B => 0x4B, // Left
            0x7C => 0x4D, // Right
            0x7D => 0x50, // Down
            0x7E => 0x48, // Up
            _ => null
        };

    private static bool IsExtendedKey(ushort originalMacKeyCode, ushort scanCode) =>
        originalMacKeyCode is 0x3D or 0x3E or 0x73 or 0x74 or 0x75 or 0x77 or 0x79 or 0x7B or 0x7C or 0x7D or 0x7E
        || scanCode is 0x47 or 0x49 or 0x4B or 0x4D or 0x4F or 0x50 or 0x51 or 0x53;

    private static void Send(INPUT input)
    {
        var inputs = new[] { input };
        _ = SendInput(1, inputs, Marshal.SizeOf<INPUT>());
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
