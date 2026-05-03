import Foundation
import CoreGraphics

/// Injects mouse + keyboard events received from the peer into the local OS via CGEventPost.
/// Applies the modifier remap table (Cmd↔Ctrl, Option↔Alt) before posting.
public final class EventInjector {
    public struct ModifierRemap {
        public var cmdToCtrl: Bool = true
        public var optionToAlt: Bool = true
        public init() {}
    }

    public var modifierRemap = ModifierRemap()
    public var assumeWindowsScanCodes = true

    private let source: CGEventSource?

    public init(source: CGEventSource? = CGEventSource(stateID: .hidSystemState)) {
        self.source = source
    }

    public func inject(_ frame: KmFrame) {
        _ = try? injectThrowing(frame)
    }

    public func injectThrowing(_ frame: KmFrame) throws {
        switch frame.type {
        case .mouseMoveRel:
            let move = try KmPayload.decodeMouseMove(frame.payload)
            let current = currentMouseLocation()
            let target = CGPoint(x: current.x + CGFloat(move.x), y: current.y + CGFloat(move.y))
            CGWarpMouseCursorPosition(target)

        case .mouseMoveAbs:
            let move = try KmPayload.decodeMouseMove(frame.payload)
            CGWarpMouseCursorPosition(CGPoint(x: CGFloat(move.x), y: CGFloat(move.y)))

        case .mouseButton:
            let button = try KmPayload.decodeMouseButton(frame.payload)
            postMouseButton(button)

        case .mouseScroll:
            let scroll = try KmPayload.decodeMouseScroll(frame.payload)
            postScroll(scroll)

        case .keyDown:
            let key = try KmPayload.decodeKey(frame.payload)
            postKey(key, isDown: true)

        case .keyUp:
            let key = try KmPayload.decodeKey(frame.payload)
            postKey(key, isDown: false)

        case .modifiersChanged:
            // Modifier state is carried on key frames. macOS does not provide a clean
            // "set all flags" event, so this frame is currently informational.
            _ = try KmPayload.decodeModifiers(frame.payload)

        case .heartbeat, .clockSync:
            break
        }
    }

    private func postMouseButton(_ button: KmPayload.MouseButton) {
        let cgButton = CGMouseButton(rawValue: UInt32(button.button)) ?? .left
        let type: CGEventType
        switch (button.button, button.isDown) {
        case (0, true): type = .leftMouseDown
        case (0, false): type = .leftMouseUp
        case (1, true): type = .rightMouseDown
        case (1, false): type = .rightMouseUp
        default: type = button.isDown ? .otherMouseDown : .otherMouseUp
        }

        CGEvent(
            mouseEventSource: source,
            mouseType: type,
            mouseCursorPosition: currentMouseLocation(),
            mouseButton: cgButton
        )?.post(tap: .cghidEventTap)
    }

    private func postScroll(_ scroll: KmPayload.MouseScroll) {
        CGEvent(
            scrollWheelEvent2Source: source,
            units: .pixel,
            wheelCount: 2,
            wheel1: scroll.deltaY,
            wheel2: scroll.deltaX,
            wheel3: 0
        )?.post(tap: .cghidEventTap)
    }

    private func postKey(_ key: KmPayload.Key, isDown: Bool) {
        let keyCode = remapKeyCode(CGKeyCode(key.keyCode))
        let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: isDown)
        event?.flags = remapFlags(CGEventFlags(rawValue: key.flags))
        event?.post(tap: .cghidEventTap)
    }

    private func currentMouseLocation() -> CGPoint {
        CGEvent(source: source)?.location ?? .zero
    }

    private func remapFlags(_ original: CGEventFlags) -> CGEventFlags {
        var flags = original

        if modifierRemap.cmdToCtrl {
            let hadCommand = original.contains(.maskCommand)
            let hadControl = original.contains(.maskControl)
            flags.remove(.maskCommand)
            flags.remove(.maskControl)
            if hadCommand { flags.insert(.maskControl) }
            if hadControl { flags.insert(.maskCommand) }
        }

        // On macOS the physical Alt key is represented as Option/Alternate.
        // The separate toggle exists for symmetry with Windows.
        if !modifierRemap.optionToAlt {
            flags.remove(.maskAlternate)
        }

        return flags
    }

    private func remapKeyCode(_ keyCode: CGKeyCode) -> CGKeyCode {
        let keyCode = assumeWindowsScanCodes ? Self.macVirtualKeyForWindowsScanCode(UInt16(keyCode)) ?? keyCode : keyCode

        guard modifierRemap.cmdToCtrl else { return keyCode }

        switch keyCode {
        case Self.leftCommandKey: return Self.leftControlKey
        case Self.rightCommandKey: return Self.rightControlKey
        case Self.leftControlKey: return Self.leftCommandKey
        case Self.rightControlKey: return Self.rightCommandKey
        default: return keyCode
        }
    }

    public static func macVirtualKeyForWindowsScanCode(_ scanCode: UInt16) -> CGKeyCode? {
        switch scanCode {
        case 0x01: return 0x35 // Escape
        case 0x02: return 0x12 // 1
        case 0x03: return 0x13 // 2
        case 0x04: return 0x14 // 3
        case 0x05: return 0x15 // 4
        case 0x06: return 0x17 // 5
        case 0x07: return 0x16 // 6
        case 0x08: return 0x1A // 7
        case 0x09: return 0x1D // 8
        case 0x0A: return 0x19 // 9
        case 0x0B: return 0x1C // 0
        case 0x0C: return 0x1B // -
        case 0x0D: return 0x18 // =
        case 0x0E: return 0x33 // Backspace
        case 0x0F: return 0x30 // Tab
        case 0x10: return 0x0C // Q
        case 0x11: return 0x0D // W
        case 0x12: return 0x0E // E
        case 0x13: return 0x0F // R
        case 0x14: return 0x11 // T
        case 0x15: return 0x10 // Y
        case 0x16: return 0x20 // U
        case 0x17: return 0x22 // I
        case 0x18: return 0x1F // O
        case 0x19: return 0x23 // P
        case 0x1A: return 0x21 // [
        case 0x1B: return 0x1E // ]
        case 0x1C: return 0x24 // Return
        case 0x1D: return leftControlKey
        case 0x1E: return 0x00 // A
        case 0x1F: return 0x01 // S
        case 0x20: return 0x02 // D
        case 0x21: return 0x03 // F
        case 0x22: return 0x05 // G
        case 0x23: return 0x04 // H
        case 0x24: return 0x26 // J
        case 0x25: return 0x28 // K
        case 0x26: return 0x25 // L
        case 0x27: return 0x29 // ;
        case 0x28: return 0x27 // '
        case 0x29: return 0x32 // `
        case 0x2A: return 0x38 // Left Shift
        case 0x2B: return 0x2A // \
        case 0x2C: return 0x06 // Z
        case 0x2D: return 0x07 // X
        case 0x2E: return 0x08 // C
        case 0x2F: return 0x09 // V
        case 0x30: return 0x0B // B
        case 0x31: return 0x2D // N
        case 0x32: return 0x2E // M
        case 0x33: return 0x2B // ,
        case 0x34: return 0x2F // .
        case 0x35: return 0x2C // /
        case 0x36: return 0x3C // Right Shift
        case 0x37: return 0x43 // Keypad *
        case 0x38: return 0x3A // Alt/Option
        case 0x39: return 0x31 // Space
        case 0x3A: return 0x39 // Caps Lock
        case 0x3B: return 0x7A // F1
        case 0x3C: return 0x78 // F2
        case 0x3D: return 0x63 // F3
        case 0x3E: return 0x76 // F4
        case 0x3F: return 0x60 // F5
        case 0x40: return 0x61 // F6
        case 0x41: return 0x62 // F7
        case 0x42: return 0x64 // F8
        case 0x43: return 0x65 // F9
        case 0x44: return 0x6D // F10
        case 0x45: return 0x47 // Num Lock / Keypad Clear
        case 0x46: return 0x6B // Scroll Lock / F14
        case 0x47: return 0x59 // Keypad 7
        case 0x48: return 0x5B // Keypad 8
        case 0x49: return 0x5C // Keypad 9
        case 0x4A: return 0x4E // Keypad -
        case 0x4B: return 0x56 // Keypad 4
        case 0x4C: return 0x57 // Keypad 5
        case 0x4D: return 0x58 // Keypad 6
        case 0x4E: return 0x45 // Keypad +
        case 0x4F: return 0x53 // Keypad 1
        case 0x50: return 0x54 // Keypad 2
        case 0x51: return 0x55 // Keypad 3
        case 0x52: return 0x52 // Keypad 0
        case 0x53: return 0x41 // Keypad decimal
        case 0x57: return 0x67 // F11
        case 0x58: return 0x6F // F12
        case 0xE01C: return 0x4C // Keypad Enter
        case 0xE01D: return rightControlKey
        case 0xE035: return 0x4B // Keypad /
        case 0xE037: return 0x69 // Print Screen / F13
        case 0xE038: return 0x3D // Right Alt / Option
        case 0xE047: return 0x73 // Home
        case 0xE048: return 0x7E // Up
        case 0xE049: return 0x74 // Page Up
        case 0xE04B: return 0x7B // Left
        case 0xE04D: return 0x7C // Right
        case 0xE04F: return 0x77 // End
        case 0xE050: return 0x7D // Down
        case 0xE051: return 0x79 // Page Down
        case 0xE052: return 0x72 // Insert / Help
        case 0xE053: return 0x75 // Forward Delete
        case 0xE05B: return leftCommandKey
        case 0xE05C: return rightCommandKey
        default: return nil
        }
    }

    private static let leftCommandKey: CGKeyCode = 0x37
    private static let rightCommandKey: CGKeyCode = 0x36
    private static let leftControlKey: CGKeyCode = 0x3B
    private static let rightControlKey: CGKeyCode = 0x3E
}
