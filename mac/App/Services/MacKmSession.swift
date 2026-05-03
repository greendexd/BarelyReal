import ApplicationServices
import BarelyRealCore
import CoreGraphics
import Foundation
import Network

final class MacKmSession {
    private let peerHost: String
    private let peerPort: UInt16
    private let direction: EdgeDirection
    private let peerScreen: PeerScreen
    private let scrollSpeed: Int
    private let log: (String) -> Void

    private let stream = UdpKmStream()
    private let tap = EventTap()
    private var bridge: EdgeBridge?
    private var sentCount = 0
    private var heartbeatPump: KmHeartbeatPump?
    private var heartbeatSeq: UInt32 = 1_000_000_000  // out-of-band, won't collide with real KM seq
    private let hotkey = HotkeyManager()

    init(peerHost: String, peerPort: UInt16, direction: EdgeDirection, peerScreen: PeerScreen, scrollSpeed: Int, log: @escaping (String) -> Void) {
        self.peerHost = peerHost
        self.peerPort = peerPort
        self.direction = direction
        self.peerScreen = peerScreen
        self.scrollSpeed = scrollSpeed
        self.log = log
    }

    func start() throws {
        guard let port = NWEndpoint.Port(rawValue: peerPort) else {
            throw KmSessionError.invalidPort(peerPort)
        }

        let endpoint = NWEndpoint.hostPort(host: .name(peerHost, nil), port: port)
        let bridge = EdgeBridge(
            direction: direction,
            peerScreen: peerScreen,
            stream: stream,
            endpoint: endpoint,
            log: log
        )
        self.bridge = bridge

        tap.scrollSpeed = scrollSpeed
        tap.suppressLocalEvents = bridge.shouldSuppressLocalEvents
        tap.onFrame = { [weak self, weak bridge, weak tap] frame in
            guard let self, let bridge else { return }
            let didSend = bridge.handle(frame)
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

        // Heartbeat keeps the receiver's link-monitor happy while the user is idle.
        // Always sent — costs ~20 datagrams/s of ~13 bytes each = 260 B/s. Trivial.
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

        // Global hotkey for force-switch (default ⌃⇧⌥⌘S).
        hotkey.onForceSwitch = { [weak self] in
            guard let self, let bridge = self.bridge else { return }
            bridge.toggleRemote()
            self.tap.suppressLocalEvents = bridge.shouldSuppressLocalEvents
            self.log("Force-switch: \(bridge.isRemote ? "entered remote" : "back to Mac")")
        }
        hotkey.register()
    }

    func stop() {
        hotkey.unregister()
        heartbeatPump?.stop()
        heartbeatPump = nil
        tap.stop()
        bridge?.stop()
        bridge = nil
        stream.close()
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

enum EdgeDirection {
    case left
    case right

    var initialRemoteX: Int32 {
        switch self {
        case .left: -24
        case .right: 24
        }
    }
}

struct PeerScreen {
    let width: Int32
    let height: Int32
}

private final class RemoteInputGuard {
    private var isActive = false
    private var cursorHidden = false
    private var pinnedPoint: CGPoint?

    func start(pinnedAt point: CGPoint) {
        guard !isActive else { return }

        pinnedPoint = point
        CGWarpMouseCursorPosition(point)
        _ = CGAssociateMouseAndMouseCursorPosition(boolean_t(0))
        if CGDisplayHideCursor(CGMainDisplayID()) == .success {
            cursorHidden = true
        }
        isActive = true
    }

    func maintainPin() {
        guard isActive, let pinnedPoint else { return }
        CGWarpMouseCursorPosition(pinnedPoint)
        if !cursorHidden, CGDisplayHideCursor(CGMainDisplayID()) == .success {
            cursorHidden = true
        }
    }

    func stop() {
        guard isActive else { return }

        if cursorHidden {
            _ = CGDisplayShowCursor(CGMainDisplayID())
            cursorHidden = false
        }
        _ = CGAssociateMouseAndMouseCursorPosition(boolean_t(1))
        pinnedPoint = nil
        isActive = false
    }

    deinit {
        stop()
    }
}

private final class EdgeBridge {
    private let direction: EdgeDirection
    private let peerScreen: PeerScreen
    private let stream: UdpKmStream
    private let endpoint: NWEndpoint
    private let log: (String) -> Void
    private let guardController = RemoteInputGuard()
    private let desktopBounds: CGRect

    private var isRemoteActive = false
    private var remoteX: Int32

    init(direction: EdgeDirection, peerScreen: PeerScreen, stream: UdpKmStream, endpoint: NWEndpoint, log: @escaping (String) -> Void) {
        self.direction = direction
        self.peerScreen = peerScreen
        self.stream = stream
        self.endpoint = endpoint
        self.log = log
        self.desktopBounds = Self.currentDesktopBounds()
        self.remoteX = direction.initialRemoteX
    }

    var shouldSuppressLocalEvents: Bool {
        isRemoteActive
    }

    @discardableResult
    func handle(_ frame: KmFrame) -> Bool {
        if !isRemoteActive {
            guard shouldEnterRemote(for: frame) else { return false }
            let entryFrame = enterRemote(reference: frame)
            stream.send(entryFrame, to: endpoint)
            return true
        }

        if shouldReturnLocal(for: frame) {
            returnLocal()
            return false
        }

        updateRemotePosition(for: frame)
        guardController.maintainPin()
        stream.send(frame, to: endpoint)
        return true
    }

    func stop() {
        returnLocal()
    }

    /// Send a frame regardless of remote/local state. Used by the heartbeat pump.
    func sendBypassingEdge(_ frame: KmFrame) {
        stream.send(frame, to: endpoint)
    }

    var isRemote: Bool { isRemoteActive }

    /// Forcibly toggle remote/local mode (used by global hotkey).
    func toggleRemote() {
        if isRemoteActive {
            returnLocal()
        } else {
            // Synthesize an "entry" frame from cursor position to seed the peer side.
            let now = UInt64(Date().timeIntervalSince1970 * 1_000_000)
            let seed = KmFrame(
                seq: UInt32.random(in: 1...1_000_000),
                timestampUs: now,
                type: .mouseMoveRel,
                payload: KmPayload.encodeMouseMove(.init(x: 0, y: 0))
            )
            let entryFrame = enterRemote(reference: seed)
            stream.send(entryFrame, to: endpoint)
        }
    }

    private func shouldEnterRemote(for frame: KmFrame) -> Bool {
        guard frame.type == .mouseMoveRel,
              let move = try? KmPayload.decodeMouseMove(frame.payload)
        else {
            return false
        }

        let location = Self.currentCursorLocation()
        switch direction {
        case .left:
            return move.x < 0 && location.x <= desktopBounds.minX + 2
        case .right:
            return move.x > 0 && location.x >= desktopBounds.maxX - 2
        }
    }

    private func shouldReturnLocal(for frame: KmFrame) -> Bool {
        guard frame.type == .mouseMoveRel,
              let move = try? KmPayload.decodeMouseMove(frame.payload)
        else {
            return false
        }

        switch direction {
        case .left:
            return move.x > 0 && remoteX + move.x >= 0
        case .right:
            return move.x < 0 && remoteX + move.x <= 0
        }
    }

    private func updateRemotePosition(for frame: KmFrame) {
        guard frame.type == .mouseMoveRel,
              let move = try? KmPayload.decodeMouseMove(frame.payload)
        else {
            return
        }

        switch direction {
        case .left:
            remoteX = min(0, remoteX + move.x)
        case .right:
            remoteX = max(0, remoteX + move.x)
        }
    }

    private func enterRemote(reference frame: KmFrame) -> KmFrame {
        isRemoteActive = true
        remoteX = direction.initialRemoteX
        let localLocation = Self.currentCursorLocation()
        guardController.start(pinnedAt: localPinPoint(localY: localLocation.y))
        let entryPoint = peerEntryPoint(localY: localLocation.y)
        log("Entered Windows at x=\(entryPoint.x), y=\(entryPoint.y)")

        return KmFrame(
            seq: frame.seq,
            timestampUs: frame.timestampUs,
            type: .mouseMoveAbs,
            payload: KmPayload.encodeMouseMove(entryPoint)
        )
    }

    private func returnLocal() {
        guard isRemoteActive else { return }
        isRemoteActive = false
        guardController.stop()

        let x = switch direction {
        case .left: desktopBounds.minX + 4
        case .right: desktopBounds.maxX - 4
        }
        CGWarpMouseCursorPosition(CGPoint(x: x, y: Self.currentCursorLocation().y))
        log("Returned to Mac")
    }

    private func localPinPoint(localY: CGFloat) -> CGPoint {
        let x = switch direction {
        case .left: desktopBounds.minX + 1
        case .right: desktopBounds.maxX - 1
        }
        return CGPoint(x: x, y: min(max(localY, desktopBounds.minY), desktopBounds.maxY - 1))
    }

    private func peerEntryPoint(localY: CGFloat) -> KmPayload.MouseMove {
        let maxX = max(peerScreen.width - 1, 0)
        let maxY = max(peerScreen.height - 1, 0)
        let x: Int32 = switch direction {
        case .left: maxX
        case .right: 0
        }
        let normalizedY = desktopBounds.height > 0
            ? min(max((localY - desktopBounds.minY) / desktopBounds.height, 0), 1)
            : 0.5
        let y = Int32((normalizedY * CGFloat(maxY)).rounded())
        return KmPayload.MouseMove(x: x, y: min(max(y, 0), maxY))
    }

    private static func currentDesktopBounds() -> CGRect {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)

        guard count > 0 else {
            return CGDisplayBounds(CGMainDisplayID())
        }

        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &displays, &count)

        return displays
            .map { CGDisplayBounds($0) }
            .reduce(CGRect.null) { $0.union($1) }
    }

    private static func currentCursorLocation() -> CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }
}
