import Foundation
import CoreGraphics

/// Captures local mouse + keyboard events via CGEventTap when this machine owns input.
/// Accessibility is required. Input Monitoring is useful on some macOS setups, but the
/// current dev build should still attempt capture when only Accessibility is granted.
public final class EventTap {
    public enum EventTapError: Error, Equatable {
        case createFailed
    }

    public var onFrame: ((KmFrame) -> Void)?
    public var onFrameWithLocation: ((KmFrame, CGPoint) -> Void)?
    public var onEmergencyReturn: (() -> Void)?
    public var suppressLocalEvents = false
    public var scrollSpeed: Int {
        get { scrollSpeedLevel }
        set { scrollSpeedLevel = min(max(newValue, 1), 20) }
    }

    public private(set) var isRunning = false

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var nextSequence: UInt32 = 0
    private var scrollRemainderX: Double = 0
    private var scrollRemainderY: Double = 0
    private var scrollSpeedLevel = 7
    private var lastCapsLockFlag: Bool?

    public init() {}

    public func start() throws {
        guard !isRunning else { return }

        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        let tap = Self.makeTap(location: .cghidEventTap, userInfo: userInfo)
            ?? Self.makeTap(location: .cgSessionEventTap, userInfo: userInfo)

        guard let tap else { throw EventTapError.createFailed }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.eventTap = tap
        self.runLoopSource = source
        self.isRunning = true
    }

    public func stop() {
        guard isRunning else { return }

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }

        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }

        runLoopSource = nil
        eventTap = nil
        isRunning = false
    }

    private static let capturedEventTypes: [CGEventType] = [
        .mouseMoved,
        .leftMouseDragged,
        .rightMouseDragged,
        .otherMouseDragged,
        .leftMouseDown,
        .leftMouseUp,
        .rightMouseDown,
        .rightMouseUp,
        .otherMouseDown,
        .otherMouseUp,
        .scrollWheel,
        .keyDown,
        .keyUp,
        .flagsChanged,
    ]

    private static let eventMask: CGEventMask = capturedEventTypes.reduce(CGEventMask(0)) { mask, type in
        mask | (CGEventMask(1) << type.rawValue)
    }

    private static let callback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let tap = Unmanaged<EventTap>.fromOpaque(userInfo).takeUnretainedValue()
        return tap.handle(type: type, event: event)
    }

    private static func makeTap(location: CGEventTapLocation, userInfo: UnsafeMutableRawPointer) -> CFMachPort? {
        CGEvent.tapCreate(
            tap: location,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: userInfo
        )
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return suppressLocalEvents ? nil : Unmanaged.passUnretained(event)
        }

        if Self.isEmergencyReturnHotkey(type: type, event: event) {
            onEmergencyReturn?()
            return nil
        }

        let location = event.location
        for frame in frames(for: type, event: event) {
            if let onFrameWithLocation {
                onFrameWithLocation(frame, location)
            } else {
                onFrame?(frame)
            }
        }

        return suppressLocalEvents ? nil : Unmanaged.passUnretained(event)
    }

    private func frames(for type: CGEventType, event: CGEvent) -> [KmFrame] {
        switch type {
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            let dx = Int32(clamping: event.getIntegerValueField(.mouseEventDeltaX))
            let dy = Int32(clamping: event.getIntegerValueField(.mouseEventDeltaY))
            guard dx != 0 || dy != 0 else { return [] }
            return [nextFrame(
                timestampUs: Self.timestampUs(for: event),
                type: .mouseMoveRel,
                payload: KmPayload.encodeMouseMove(.init(x: dx, y: dy))
            )]

        case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp:
            let button = UInt8(clamping: event.getIntegerValueField(.mouseEventButtonNumber))
            let isDown = type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown
            return [nextFrame(
                timestampUs: Self.timestampUs(for: event),
                type: .mouseButton,
                payload: KmPayload.encodeMouseButton(.init(button: button, isDown: isDown))
            )]

        case .scrollWheel:
            let scroll = normalizedWindowsScroll(for: event)
            guard scroll.deltaX != 0 || scroll.deltaY != 0 else { return [] }
            return [nextFrame(
                timestampUs: Self.timestampUs(for: event),
                type: .mouseScroll,
                payload: KmPayload.encodeMouseScroll(scroll)
            )]

        case .keyDown, .keyUp:
            let keyCode = UInt16(clamping: event.getIntegerValueField(.keyboardEventKeycode))
            return [nextFrame(
                timestampUs: Self.timestampUs(for: event),
                type: type == .keyDown ? .keyDown : .keyUp,
                payload: KmPayload.encodeKey(.init(keyCode: keyCode, flags: event.flags.rawValue))
            )]

        case .flagsChanged:
            return modifierFrames(for: event)

        default:
            return []
        }
    }

    private func normalizedWindowsScroll(for event: CGEvent) -> KmPayload.MouseScroll {
        let lineY = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let lineX = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
        let scale = scrollDeltaScale

        if lineX != 0 || lineY != 0 {
            scrollRemainderX += Double(lineX) * scale
            scrollRemainderY += Double(lineY) * scale
            return KmPayload.MouseScroll(
                deltaX: flushScrollRemainder(&scrollRemainderX),
                deltaY: flushScrollRemainder(&scrollRemainderY)
            )
        }

        let pointY = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
        let pointX = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
        scrollRemainderX += Double(pointX) * scale / 10
        scrollRemainderY += Double(pointY) * scale / 10

        let deltaX = flushScrollRemainder(&scrollRemainderX)
        let deltaY = flushScrollRemainder(&scrollRemainderY)
        return KmPayload.MouseScroll(deltaX: deltaX, deltaY: deltaY)
    }

    private func flushScrollRemainder(_ value: inout Double) -> Int32 {
        guard abs(value) >= 1 else { return 0 }

        let whole = value > 0 ? floor(value) : ceil(value)
        value -= whole
        return Int32(clamping: Int64(whole))
    }

    private var scrollDeltaScale: Double {
        // Old smoke mode sent 120 per line event. This app scale is intentionally
        // much softer because macOS emits many small scroll events in a burst.
        let normalized = Double(scrollSpeedLevel) / 20
        return 0.35 + pow(normalized, 1.8) * 23.65
    }

    private func modifierFrames(for event: CGEvent) -> [KmFrame] {
        let timestampUs = Self.timestampUs(for: event)
        let keyCode = UInt16(clamping: event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags.rawValue

        if keyCode == Self.capsLockKey {
            let isEnabled = event.flags.contains(.maskAlphaShift)
            defer { lastCapsLockFlag = isEnabled }
            guard lastCapsLockFlag != isEnabled else { return [] }

            return [
                nextFrame(timestampUs: timestampUs, type: .keyDown, payload: KmPayload.encodeKey(.init(keyCode: keyCode, flags: flags))),
                nextFrame(timestampUs: timestampUs, type: .keyUp, payload: KmPayload.encodeKey(.init(keyCode: keyCode, flags: flags))),
            ]
        }

        guard let flag = Self.modifierFlag(for: keyCode) else {
            return [nextFrame(timestampUs: timestampUs, type: .modifiersChanged, payload: KmPayload.encodeModifiers(flags: flags))]
        }

        return [nextFrame(
            timestampUs: timestampUs,
            type: event.flags.contains(flag) ? .keyDown : .keyUp,
            payload: KmPayload.encodeKey(.init(keyCode: keyCode, flags: flags))
        )]
    }

    private func nextFrame(timestampUs: UInt64, type: KmType, payload: Data) -> KmFrame {
        let seq = nextSequence
        nextSequence &+= 1
        return KmFrame(seq: seq, timestampUs: timestampUs, type: type, payload: payload)
    }

    private static func timestampUs(for event: CGEvent) -> UInt64 {
        UInt64(Date().timeIntervalSince1970 * 1_000_000)
    }

    public static func isEmergencyReturnHotkey(keyCode: UInt16, flagsRaw: UInt64) -> Bool {
        guard keyCode == emergencyReturnKey else { return false }
        let flags = CGEventFlags(rawValue: flagsRaw)
        return flags.contains(.maskControl)
            && flags.contains(.maskAlternate)
            && flags.contains(.maskCommand)
    }

    private static func isEmergencyReturnHotkey(type: CGEventType, event: CGEvent) -> Bool {
        guard type == .keyDown else { return false }
        guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return false }
        let keyCode = UInt16(clamping: event.getIntegerValueField(.keyboardEventKeycode))
        return isEmergencyReturnHotkey(keyCode: keyCode, flagsRaw: event.flags.rawValue)
    }

    private static func modifierFlag(for keyCode: UInt16) -> CGEventFlags? {
        switch keyCode {
        case 0x38, 0x3C: return .maskShift
        case 0x3B, 0x3E: return .maskControl
        case 0x3A, 0x3D: return .maskAlternate
        case 0x37, 0x36: return .maskCommand
        default: return nil
        }
    }

    private static let capsLockKey: UInt16 = 0x39
    private static let emergencyReturnKey: UInt16 = 0x35 // Escape
}
