import Carbon.HIToolbox
import Foundation

/// Global hotkey via Carbon `RegisterEventHotKey`. Default: `⌃⇧⌥⌘S`.
///
/// `register` installs an event handler on the main run loop. `onForceSwitch` fires when the
/// combo is pressed; the handler is called on the main thread.
public final class HotkeyManager {
    public struct Combo: Equatable {
        /// Carbon virtual key code (kVK_*). Default: kVK_ANSI_S.
        public var keyCode: UInt32
        /// Bitmask of `cmdKey | shiftKey | controlKey | optionKey`.
        public var modifiers: UInt32

        public static let defaultForceSwitch = Combo(
            keyCode: UInt32(kVK_ANSI_S),
            modifiers: UInt32(cmdKey | shiftKey | controlKey | optionKey)
        )

        public init(keyCode: UInt32, modifiers: UInt32) {
            self.keyCode = keyCode
            self.modifiers = modifiers
        }
    }

    public var onForceSwitch: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private static var hotkeySignature: OSType = OSType("BRYR".utf8.reduce(0) { ($0 << 8) | UInt32($1) })

    public init() {}

    public func register(combo: Combo = .defaultForceSwitch) {
        unregister()

        // Install event handler
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let opaque = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetEventDispatcherTarget(), { _, eventRef, userData in
            guard let userData else { return noErr }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { manager.onForceSwitch?() }
            return noErr
        }, 1, &spec, opaque, &handlerRef)

        let hotKeyID = EventHotKeyID(signature: HotkeyManager.hotkeySignature, id: 1)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            combo.keyCode,
            combo.modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &ref
        )
        if status == noErr {
            hotKeyRef = ref
        }
    }

    public func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }

    deinit {
        unregister()
    }
}
