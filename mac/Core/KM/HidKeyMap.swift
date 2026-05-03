import Foundation

/// HID Usage IDs (USB HID Usage Tables, Page 0x07) ↔ macOS virtual key codes (`kVK_*`).
///
/// These tables are the **canonical wire format** for BRP per the spec. The current Week 2
/// scaffold still ships native scan codes on the wire because both ends are hand-tuned for
/// each other; once both sides switch atomically, the encoder/decoder will use HID values.
///
/// Coverage: A-Z, 0-9, function keys F1-F15, navigation, common punctuation, modifiers.
/// Anything not in the table simply round-trips to/from `nil`.
public enum HidKeyMap {

    // MARK: - kVK ↔ HID

    public static func hid(forKVK kvk: UInt16) -> UInt16? {
        kvkToHid[kvk]
    }

    public static func kvk(forHID hid: UInt16) -> UInt16? {
        hidToKvk[hid]
    }

    // MARK: - Modifier bitmask

    /// BRP modifier bitmask (see protocol/BRP-1.0.md § Modifier bitmask).
    public struct Modifiers: OptionSet, Sendable {
        public let rawValue: UInt16
        public init(rawValue: UInt16) { self.rawValue = rawValue }

        public static let leftShift   = Modifiers(rawValue: 0x0001)
        public static let rightShift  = Modifiers(rawValue: 0x0002)
        public static let leftCtrl    = Modifiers(rawValue: 0x0004)
        public static let rightCtrl   = Modifiers(rawValue: 0x0008)
        public static let leftAlt     = Modifiers(rawValue: 0x0010)
        public static let rightAlt    = Modifiers(rawValue: 0x0020)
        public static let leftGui     = Modifiers(rawValue: 0x0040)
        public static let rightGui    = Modifiers(rawValue: 0x0080)
        public static let capsLock    = Modifiers(rawValue: 0x0100)
        public static let numLock     = Modifiers(rawValue: 0x0200)
        public static let scrollLock  = Modifiers(rawValue: 0x0400)
    }

    /// Convert macOS `CGEventFlags.rawValue` (passed as UInt64) into a canonical BRP bitmask.
    /// L/R distinction is folded into Left-only because CGEventFlags doesn't expose sides cleanly
    /// without extra device-state lookup.
    public static func modifiers(fromCGEventFlags rawFlags: UInt64) -> Modifiers {
        var mods = Modifiers()
        // CGEventFlags bit values from CoreGraphics:
        let maskShift     : UInt64 = 0x0002_0000
        let maskControl   : UInt64 = 0x0004_0000
        let maskAlternate : UInt64 = 0x0008_0000
        let maskCommand   : UInt64 = 0x0010_0000
        let maskAlphaShift: UInt64 = 0x0001_0000  // Caps Lock
        let maskNumericPad: UInt64 = 0x0020_0000  // Num Lock proxy
        if rawFlags & maskShift     != 0 { mods.insert(.leftShift) }
        if rawFlags & maskControl   != 0 { mods.insert(.leftCtrl) }
        if rawFlags & maskAlternate != 0 { mods.insert(.leftAlt) }
        if rawFlags & maskCommand   != 0 { mods.insert(.leftGui) }
        if rawFlags & maskAlphaShift != 0 { mods.insert(.capsLock) }
        if rawFlags & maskNumericPad != 0 { mods.insert(.numLock) }
        return mods
    }

    /// Convert a canonical BRP modifier bitmask back to macOS-flavoured CGEventFlags raw bits.
    public static func cgEventFlagsRaw(from mods: Modifiers) -> UInt64 {
        var raw: UInt64 = 0
        if !mods.intersection([.leftShift, .rightShift]).isEmpty { raw |= 0x0002_0000 }
        if !mods.intersection([.leftCtrl, .rightCtrl]).isEmpty   { raw |= 0x0004_0000 }
        if !mods.intersection([.leftAlt, .rightAlt]).isEmpty     { raw |= 0x0008_0000 }
        if !mods.intersection([.leftGui, .rightGui]).isEmpty     { raw |= 0x0010_0000 }
        if mods.contains(.capsLock)   { raw |= 0x0001_0000 }
        if mods.contains(.numLock)    { raw |= 0x0020_0000 }
        return raw
    }

    // MARK: - Tables

    /// macOS kVK_* (Carbon `HIToolbox/Events.h`) → HID Usage Page 0x07.
    /// Subset that BarelyReal supports today. Extend as needed.
    private static let kvkToHid: [UInt16: UInt16] = [
        0x00: 0x04, 0x0B: 0x05, 0x08: 0x06, 0x02: 0x07, 0x0E: 0x08,
        0x03: 0x09, 0x05: 0x0A, 0x04: 0x0B, 0x22: 0x0C, 0x26: 0x0D,
        0x28: 0x0E, 0x25: 0x0F, 0x2E: 0x10, 0x2D: 0x11, 0x1F: 0x12,
        0x23: 0x13, 0x0C: 0x14, 0x0F: 0x15, 0x01: 0x16, 0x11: 0x17,
        0x20: 0x18, 0x09: 0x19, 0x0D: 0x1A, 0x07: 0x1B, 0x10: 0x1C,
        0x06: 0x1D,
        0x12: 0x1E, 0x13: 0x1F, 0x14: 0x20, 0x15: 0x21, 0x17: 0x22,
        0x16: 0x23, 0x1A: 0x24, 0x1C: 0x25, 0x19: 0x26, 0x1D: 0x27,
        0x24: 0x28, 0x35: 0x29, 0x33: 0x2A, 0x30: 0x2B, 0x31: 0x2C,
        0x1B: 0x2D, 0x18: 0x2E, 0x21: 0x2F, 0x1E: 0x30, 0x2A: 0x31,
        0x29: 0x33, 0x27: 0x34, 0x32: 0x35, 0x2B: 0x36, 0x2F: 0x37,
        0x2C: 0x38, 0x39: 0x39,
        0x7A: 0x3A, 0x78: 0x3B, 0x63: 0x3C, 0x76: 0x3D, 0x60: 0x3E,
        0x61: 0x3F, 0x62: 0x40, 0x64: 0x41, 0x65: 0x42, 0x6D: 0x43,
        0x67: 0x44, 0x6F: 0x45,
        0x69: 0x46, 0x6B: 0x47, 0x71: 0x48,
        0x72: 0x49, 0x73: 0x4A, 0x74: 0x4B, 0x75: 0x4C, 0x77: 0x4D, 0x79: 0x4E,
        0x7C: 0x4F, 0x7B: 0x50, 0x7D: 0x51, 0x7E: 0x52,
        0x3B: 0xE0, 0x38: 0xE1, 0x3A: 0xE2, 0x37: 0xE3,
        0x3E: 0xE4, 0x3C: 0xE5, 0x3D: 0xE6, 0x36: 0xE7,
    ]

    private static let hidToKvk: [UInt16: UInt16] = {
        var dict: [UInt16: UInt16] = [:]
        for (k, v) in kvkToHid { dict[v] = k }
        return dict
    }()
}
