import AppKit
import ApplicationServices
import BarelyRealCore
import CoreGraphics
import Foundation
import Network

final class MacKmSession {
    private let peerHost: String
    private let peerPort: UInt16
    private let localPeerId: String
    private let remotePeerId: String
    private let layoutProvider: () -> Layout
    private let remoteDisplaysProvider: () -> [DisplayInfo]
    private let scrollSpeed: Int
    private let kmSharedSecret: String
    private let log: (String) -> Void

    private let stream = UdpKmStream()
    private let tap = EventTap()
    private var bridge: EdgeBridge?
    private var sentCount = 0
    private var heartbeatPump: KmHeartbeatPump?
    private var heartbeatSeq: UInt32 = 1_000_000_000
    private let hotkey = HotkeyManager()
    private var safetyObserverTokens: [NSObjectProtocol] = []

    init(
        peerHost: String,
        peerPort: UInt16,
        localPeerId: String,
        remotePeerId: String,
        layoutProvider: @escaping () -> Layout,
        remoteDisplaysProvider: @escaping () -> [DisplayInfo],
        scrollSpeed: Int,
        kmSharedSecret: String,
        log: @escaping (String) -> Void
    ) {
        self.peerHost = peerHost
        self.peerPort = peerPort
        self.localPeerId = localPeerId
        self.remotePeerId = remotePeerId
        self.layoutProvider = layoutProvider
        self.remoteDisplaysProvider = remoteDisplaysProvider
        self.scrollSpeed = scrollSpeed
        self.kmSharedSecret = kmSharedSecret
        self.log = log
    }

    func start() throws {
        guard let port = NWEndpoint.Port(rawValue: peerPort) else {
            throw KmSessionError.invalidPort(peerPort)
        }

        let endpoint = NWEndpoint.hostPort(host: .name(peerHost, nil), port: port)
        stream.authenticationSecret = kmSharedSecret
        if UdpKmAuthenticator(sharedSecret: kmSharedSecret) != nil {
            log("KM UDP authentication enabled.")
        } else {
            log("KM UDP authentication disabled; set a shared secret in Settings.")
        }

        let bridge = EdgeBridge(
            localPeerId: localPeerId,
            remotePeerId: remotePeerId,
            layoutProvider: layoutProvider,
            remoteDisplaysProvider: remoteDisplaysProvider,
            stream: stream,
            endpoint: endpoint,
            log: log
        )
        self.bridge = bridge

        tap.scrollSpeed = scrollSpeed
        tap.suppressLocalEvents = bridge.shouldSuppressLocalEvents
        tap.onEmergencyReturn = { [weak bridge, weak tap] in
            guard let bridge else { return }
            bridge.forceReturnLocal(reason: "Emergency return to Mac (Ctrl+Option+Command+Esc)")
            tap?.suppressLocalEvents = bridge.shouldSuppressLocalEvents
        }
        tap.onFrameWithLocation = { [weak self, weak bridge, weak tap] frame, location in
            guard let self, let bridge else { return }
            let didSend = bridge.handle(frame, localCursorLocation: location)
            tap?.suppressLocalEvents = bridge.shouldSuppressLocalEvents
            if didSend {
                self.sentCount += 1
                self.heartbeatPump?.noteFrameSent()
                if self.sentCount == 1 || self.sentCount % 500 == 0 {
                    self.log("KM frames sent: \(self.sentCount)")
                }
            }
        }

        try tap.start()

        let pump = KmHeartbeatPump(
            nextSeq: { [weak self] in
                guard let self else { return 0 }
                self.heartbeatSeq &+= 1
                return self.heartbeatSeq
            },
            send: { [weak self, weak bridge] frame in
                guard let self, let bridge else { return }
                bridge.sendBypassingEdge(frame)
                self.heartbeatPump?.noteFrameSent()
            }
        )
        pump.start()
        self.heartbeatPump = pump

        hotkey.onForceSwitch = { [weak self] in
            guard let self, let bridge = self.bridge else { return }
            bridge.toggleRemote()
            self.tap.suppressLocalEvents = bridge.shouldSuppressLocalEvents
            self.log("Force-switch: \(bridge.isRemote ? "entered remote" : "back to Mac")")
        }
        hotkey.register()
        installSafetyObservers()
    }

    func stop() {
        removeSafetyObservers()
        hotkey.unregister()
        heartbeatPump?.stop()
        heartbeatPump = nil
        tap.onFrameWithLocation = nil
        tap.stop()
        bridge?.stop()
        bridge = nil
        stream.close()
    }

    private func installSafetyObservers() {
        removeSafetyObservers()
        let center = NSWorkspace.shared.notificationCenter
        let notifications: [(Notification.Name, String)] = [
            (NSWorkspace.sessionDidResignActiveNotification, "Returned to Mac because macOS session resigned active"),
            (NSWorkspace.screensDidSleepNotification, "Returned to Mac because displays went to sleep"),
            (NSWorkspace.willSleepNotification, "Returned to Mac because Mac is going to sleep"),
        ]

        safetyObserverTokens = notifications.map { notification, reason in
            center.addObserver(forName: notification, object: nil, queue: .main) { [weak self] _ in
                self?.forceReturnToMac(reason: reason)
            }
        }
    }

    private func removeSafetyObservers() {
        let center = NSWorkspace.shared.notificationCenter
        for token in safetyObserverTokens {
            center.removeObserver(token)
        }
        safetyObserverTokens.removeAll()
    }

    private func forceReturnToMac(reason: String) {
        bridge?.forceReturnLocal(reason: reason)
        tap.suppressLocalEvents = bridge?.shouldSuppressLocalEvents ?? false
    }
}

enum KmSessionError: Error, CustomStringConvertible {
    case invalidPort(UInt16)

    var description: String {
        switch self {
        case .invalidPort(let port): "Invalid KM port: \(port)"
        }
    }
}

private final class RemoteInputGuard {
    private var isActive = false
    private var hiddenDisplays: [CGDirectDisplayID] = []
    private var pinnedPoint: CGPoint?
    private var lastPinMaintenance: CFAbsoluteTime = 0
    private var lastAssociationAssert: CFAbsoluteTime = 0

    func start(pinnedAt point: CGPoint) {
        guard !isActive else { return }
        pinnedPoint = point
        let now = CFAbsoluteTimeGetCurrent()
        lastPinMaintenance = now
        lastAssociationAssert = now
        CGWarpMouseCursorPosition(point)
        _ = CGAssociateMouseAndMouseCursorPosition(boolean_t(0))
        hideCursorOnActiveDisplays()
        isActive = true
    }

    func maintainPin(force: Bool = false) {
        guard isActive else { return }
        if hiddenDisplays.isEmpty {
            hideCursorOnActiveDisplays()
        }
        guard let pinnedPoint else { return }

        let now = CFAbsoluteTimeGetCurrent()
        if now - lastAssociationAssert >= Self.associationAssertInterval {
            _ = CGAssociateMouseAndMouseCursorPosition(boolean_t(0))
            lastAssociationAssert = now
        }

        guard force || now - lastPinMaintenance >= Self.pinCheckInterval else { return }
        lastPinMaintenance = now

        let current = CGEvent(source: nil)?.location ?? pinnedPoint
        let dx = abs(current.x - pinnedPoint.x)
        let dy = abs(current.y - pinnedPoint.y)
        if dx > Self.pinDriftTolerance || dy > Self.pinDriftTolerance {
            CGWarpMouseCursorPosition(pinnedPoint)
        }
    }

    func stop() {
        guard isActive else { return }
        for display in hiddenDisplays {
            _ = CGDisplayShowCursor(display)
        }
        hiddenDisplays.removeAll()
        _ = CGAssociateMouseAndMouseCursorPosition(boolean_t(1))
        pinnedPoint = nil
        lastPinMaintenance = 0
        lastAssociationAssert = 0
        isActive = false
    }

    deinit { stop() }

    private func hideCursorOnActiveDisplays() {
        for display in Self.activeDisplays() where !hiddenDisplays.contains(display) {
            if CGDisplayHideCursor(display) == .success {
                hiddenDisplays.append(display)
            }
        }
    }

    private static func activeDisplays() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        guard count > 0 else { return [CGMainDisplayID()] }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &displays, &count)
        return Array(displays.prefix(Int(count)))
    }

    private static let pinCheckInterval: CFTimeInterval = 0.016
    private static let associationAssertInterval: CFTimeInterval = 0.25
    private static let pinDriftTolerance: CGFloat = 0.5
}

private final class EdgeBridge {
    private let localPeerId: String
    private let remotePeerId: String
    private let layoutProvider: () -> Layout
    private let remoteDisplaysProvider: () -> [DisplayInfo]
    private let stream: UdpKmStream
    private let endpoint: NWEndpoint
    private let log: (String) -> Void
    private let guardController = RemoteInputGuard()

    private var isRemoteActive = false
    private var cachedLayout = Layout(screens: [])
    private var cachedLayoutAt: CFAbsoluteTime = 0
    private var activeLayoutSnapshot: Layout?
    private var remoteVirtualPoint: CGPoint?
    private var pinnedLocalPoint: CGPoint?

    init(
        localPeerId: String,
        remotePeerId: String,
        layoutProvider: @escaping () -> Layout,
        remoteDisplaysProvider: @escaping () -> [DisplayInfo],
        stream: UdpKmStream,
        endpoint: NWEndpoint,
        log: @escaping (String) -> Void
    ) {
        self.localPeerId = localPeerId
        self.remotePeerId = remotePeerId
        self.layoutProvider = layoutProvider
        self.remoteDisplaysProvider = remoteDisplaysProvider
        self.stream = stream
        self.endpoint = endpoint
        self.log = log
    }

    var shouldSuppressLocalEvents: Bool { isRemoteActive }
    var isRemote: Bool { isRemoteActive }

    @discardableResult
    func handle(_ frame: KmFrame, localCursorLocation: CGPoint? = nil) -> Bool {
        if !isRemoteActive {
            guard let entry = entryFrameIfCrossing(frame, localCursorLocation: localCursorLocation) else { return false }
            stream.send(entry, to: endpoint)
            return true
        }

        if shouldReturnLocal(for: frame) {
            returnLocal(reason: "Returned to Mac")
            return false
        }

        updateRemotePosition(for: frame)
        guardController.maintainPin(force: frame.type == .mouseMoveRel)
        stream.send(frame, to: endpoint)
        return true
    }

    func stop() {
        returnLocal(reason: "Returned to Mac")
    }

    func sendBypassingEdge(_ frame: KmFrame) {
        stream.send(frame, to: endpoint)
    }

    func toggleRemote() {
        if isRemoteActive {
            returnLocal(reason: "Returned to Mac")
            return
        }

        let layout = layoutProvider()
        guard let remote = layout.screens(peerId: remotePeerId).first else {
            log("No remote screen in layout")
            return
        }
        let targetVirtual = CGPoint(x: remote.x + remote.width / 2, y: remote.y + remote.height / 2)
        enterRemote(virtualPoint: targetVirtual, reference: KmFrame(
            seq: UInt32.random(in: 1...1_000_000),
            timestampUs: UInt64(Date().timeIntervalSince1970 * 1_000_000),
            type: .mouseMoveRel,
            payload: KmPayload.encodeMouseMove(.init(x: 0, y: 0))
        )).map { stream.send($0, to: endpoint) }
    }

    func forceReturnLocal(reason: String) {
        guard isRemoteActive else {
            log("\(reason): already on Mac")
            return
        }
        returnLocal(reason: reason)
    }

    private func entryFrameIfCrossing(_ frame: KmFrame, localCursorLocation: CGPoint?) -> KmFrame? {
        guard frame.type == .mouseMoveRel,
              let move = try? KmPayload.decodeMouseMove(frame.payload)
        else { return nil }

        let current = localCursorLocation ?? Self.currentCursorLocation()
        let projected = CGPoint(x: current.x + CGFloat(move.x), y: current.y + CGFloat(move.y))
        let layout = currentLayout()
        guard layout.screen(at: Int(current.x.rounded()), Int(current.y.rounded()))?.peerId == localPeerId,
              let target = layout.screen(at: Int(projected.x.rounded()), Int(projected.y.rounded())),
              target.peerId == remotePeerId
        else { return nil }

        return enterRemote(
            virtualPoint: entryPoint(projected: projected, target: target, move: move),
            reference: frame,
            localPinPoint: current,
            layoutSnapshot: layout
        )
    }

    private func enterRemote(virtualPoint: CGPoint,
                             reference frame: KmFrame,
                             localPinPoint: CGPoint? = nil,
                             layoutSnapshot: Layout? = nil) -> KmFrame? {
        let layout = layoutSnapshot ?? currentLayout()
        guard let target = layout.screen(at: Int(virtualPoint.x.rounded()), Int(virtualPoint.y.rounded())),
              target.peerId == remotePeerId
        else { return nil }

        isRemoteActive = true
        activeLayoutSnapshot = layout
        remoteVirtualPoint = virtualPoint
        let current = localPinPoint ?? Self.currentCursorLocation()
        pinnedLocalPoint = current
        guardController.start(pinnedAt: current)

        let native = remoteNativePoint(for: virtualPoint, in: target)
        log("Entered Windows screen \(target.screenId) at x=\(native.x), y=\(native.y)")
        return KmFrame(
            seq: frame.seq,
            timestampUs: frame.timestampUs,
            type: .mouseMoveAbs,
            payload: KmPayload.encodeMouseMove(.init(x: Int32(native.x.rounded()), y: Int32(native.y.rounded())))
        )
    }

    private func shouldReturnLocal(for frame: KmFrame) -> Bool {
        guard frame.type == .mouseMoveRel,
              let move = try? KmPayload.decodeMouseMove(frame.payload),
              let remoteVirtualPoint
        else { return false }

        let projected = CGPoint(x: remoteVirtualPoint.x + CGFloat(move.x), y: remoteVirtualPoint.y + CGFloat(move.y))
        let target = (activeLayoutSnapshot ?? currentLayout()).screen(at: Int(projected.x.rounded()), Int(projected.y.rounded()))
        if target?.peerId == localPeerId {
            pinnedLocalPoint = projected
            return true
        }
        return false
    }

    private func updateRemotePosition(for frame: KmFrame) {
        guard frame.type == .mouseMoveRel,
              let move = try? KmPayload.decodeMouseMove(frame.payload),
              let point = remoteVirtualPoint
        else { return }
        remoteVirtualPoint = CGPoint(x: point.x + CGFloat(move.x), y: point.y + CGFloat(move.y))
    }

    private func returnLocal(reason: String) {
        guard isRemoteActive else { return }
        isRemoteActive = false
        guardController.stop()
        if let pinnedLocalPoint {
            CGWarpMouseCursorPosition(pinnedLocalPoint)
        }
        activeLayoutSnapshot = nil
        remoteVirtualPoint = nil
        pinnedLocalPoint = nil
        log(reason)
    }

    private func currentLayout() -> Layout {
        let now = CFAbsoluteTimeGetCurrent()
        if now - cachedLayoutAt <= Self.layoutCacheDuration {
            return cachedLayout
        }

        cachedLayout = layoutProvider()
        cachedLayoutAt = now
        return cachedLayout
    }

    private func remoteNativePoint(for virtualPoint: CGPoint, in layoutScreen: ScreenRect) -> CGPoint {
        if let native = remoteDisplaysProvider().first(where: { $0.screenId == layoutScreen.screenId }) {
            let dx = virtualPoint.x - CGFloat(layoutScreen.x)
            let dy = virtualPoint.y - CGFloat(layoutScreen.y)
            return CGPoint(x: CGFloat(native.x) + dx, y: CGFloat(native.y) + dy)
        }
        return CGPoint(
            x: virtualPoint.x - CGFloat(layoutScreen.x),
            y: virtualPoint.y - CGFloat(layoutScreen.y)
        )
    }

    private static func currentCursorLocation() -> CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    private func entryPoint(projected: CGPoint, target: ScreenRect, move: KmPayload.MouseMove) -> CGPoint {
        var x = min(max(projected.x, CGFloat(target.x)), CGFloat(target.maxX - 1))
        var y = min(max(projected.y, CGFloat(target.y)), CGFloat(target.maxY - 1))
        let inset = CGFloat(Self.edgeEntryInset)

        if abs(move.x) >= abs(move.y), move.x != 0 {
            x = move.x > 0 ? CGFloat(target.x) + inset : CGFloat(target.maxX - 1) - inset
        } else if move.y != 0 {
            y = move.y > 0 ? CGFloat(target.y) + inset : CGFloat(target.maxY - 1) - inset
        }

        return CGPoint(
            x: min(max(x, CGFloat(target.x)), CGFloat(target.maxX - 1)),
            y: min(max(y, CGFloat(target.y)), CGFloat(target.maxY - 1))
        )
    }

    private static let edgeEntryInset = 24
    private static let layoutCacheDuration: CFTimeInterval = 0.20
}
