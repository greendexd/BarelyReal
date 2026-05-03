import ApplicationServices
import Foundation
import Network
import BarelyRealCore

let arguments = Array(CommandLine.arguments.dropFirst())

guard let command = arguments.first, command != "-h", command != "--help", command != "help" else {
    printUsage()
    exit(0)
}

do {
    switch command {
    case "udp-loopback":
        try runUdpLoopback(arguments)
    case "capture":
        try runCapture(arguments)
    case "send":
        try runSend(arguments)
    case "receive":
        try runReceive(arguments)
    case "inject-mouse":
        try runInjectMouse(arguments)
    case "inject-key":
        try runInjectKey(arguments)
    default:
        fputs("Unknown command: \(command)\n", stderr)
        printUsage()
        exit(2)
    }
} catch {
    fputs("\(error)\n", stderr)
    exit(1)
}

private func runUdpLoopback(_ arguments: [String]) throws {
    let portValue = arguments.count >= 2 ? UInt16(arguments[1]) ?? 24_801 : 24_801
    guard let port = NWEndpoint.Port(rawValue: portValue) else {
        throw SmokeError.invalidPort(portValue)
    }

    let stream = UdpKmStream()
    let semaphore = DispatchSemaphore(value: 0)
    let expected = KmFrame(seq: 7, timestampUs: nowUs(), type: .heartbeat)
    var received: KmFrame?

    stream.onFrame = { frame in
        received = frame
        semaphore.signal()
    }

    try stream.bind(localPort: portValue)
    usleep(200_000)
    stream.send(expected, to: .hostPort(host: .ipv4(IPv4Address("127.0.0.1")!), port: port))

    let result = semaphore.wait(timeout: .now() + 3)
    stream.close()

    guard result == .success, let received else {
        throw SmokeError.timeout("UDP loopback timed out")
    }

    guard received == expected else {
        throw SmokeError.mismatch(expected: describe(expected), actual: describe(received))
    }

    print("UDP loopback ok on 127.0.0.1:\(portValue): \(describe(received))")
}

private func runCapture(_ arguments: [String]) throws {
    let seconds = arguments.count >= 2 ? Double(arguments[1]) ?? 10 : 10

    if !AXIsProcessTrusted() {
        print("Accessibility permission is not granted for this terminal/app.")
        print("Open System Settings -> Privacy & Security -> Accessibility and enable your terminal.")
    }

    let tap = EventTap()
    tap.onFrame = { frame in
        print(describe(frame))
        fflush(stdout)
    }

    try tap.start()

    print("Capturing KM frames for \(Int(seconds))s. Press Ctrl+C to stop.")
    let signalSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    signal(SIGINT, SIG_IGN)
    signalSource.setEventHandler {
        tap.stop()
        CFRunLoopStop(CFRunLoopGetMain())
    }
    signalSource.resume()

    DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
        tap.stop()
        CFRunLoopStop(CFRunLoopGetMain())
    }

    CFRunLoopRun()
    print("Capture stopped.")
}

private func runSend(_ arguments: [String]) throws {
    guard arguments.count >= 2 else {
        throw SmokeError.usage("send requires peer host: send <peerHost> [peerPort] [seconds]")
    }

    let host = arguments[1]
    let portValue = arguments.count >= 3 ? UInt16(arguments[2]) ?? 24_801 : 24_801
    let seconds = arguments.count >= 4 ? Double(arguments[3]) ?? 0 : 0
    let mirrorMode = arguments.contains("--mirror")
    let immediateRemoteMode = arguments.contains("--remote")
    let edgeDirection: EdgeDirection = arguments.contains("--peer-left") || arguments.contains("--windows-left") ? .left : .right
    let peerScreen = parsePeerScreen(arguments) ?? PeerScreen(width: 1_920, height: 1_080)
    guard let port = NWEndpoint.Port(rawValue: portValue) else {
        throw SmokeError.invalidPort(portValue)
    }

    if !AXIsProcessTrusted() {
        print("Accessibility permission is not granted for this terminal/app.")
        print("Open System Settings -> Privacy & Security -> Accessibility and enable your terminal.")
    }

    let stream = UdpKmStream()
    let tap = EventTap()
    let endpoint = NWEndpoint.hostPort(host: .name(host, nil), port: port)
    let bridge = EdgeBridge(
        enabled: !mirrorMode,
        startsActive: immediateRemoteMode,
        direction: edgeDirection,
        peerScreen: peerScreen,
        stream: stream,
        endpoint: endpoint
    )
    var sentCount = 0

    tap.suppressLocalEvents = bridge.shouldSuppressLocalEvents
    tap.onFrame = { frame in
        let didSend = bridge.handle(frame)
        tap.suppressLocalEvents = bridge.shouldSuppressLocalEvents
        if didSend {
            sentCount += 1
        }
        if didSend && (sentCount <= 10 || sentCount % 100 == 0) {
            print("sent \(describe(frame))")
            fflush(stdout)
        }
    }

    try tap.start()
    print("Sending KM frames to \(host):\(portValue). Mode: \(mirrorMode ? "mirror" : immediateRemoteMode ? "remote" : "edge"). Press Ctrl+C to stop.")
    if !mirrorMode && !immediateRemoteMode {
        print(edgeDirection.enterHint)
        print("Peer screen assumed \(peerScreen.width)x\(peerScreen.height). Override with --peer-size WIDTHxHEIGHT if needed.")
    }

    runUntilStopped(seconds: seconds) {
        tap.stop()
        stream.close()
        bridge.stop()
        print("Send stopped. Frames sent: \(sentCount)")
    }
}

private func runReceive(_ arguments: [String]) throws {
    let portValue = arguments.count >= 2 ? UInt16(arguments[1]) ?? 24_801 : 24_801
    let seconds = arguments.count >= 3 ? Double(arguments[2]) ?? 0 : 0
    let stream = UdpKmStream()
    let injector = EventInjector()
    var receivedCount = 0

    stream.onFrame = { frame in
        receivedCount += 1
        do {
            try injector.injectThrowing(frame)
        } catch {
            fputs("inject failed: \(error)\n", stderr)
        }

        if receivedCount <= 10 || receivedCount % 100 == 0 {
            print("received \(describe(frame))")
            fflush(stdout)
        }
    }

    try stream.bind(localPort: portValue)
    print("Receiving KM frames on UDP :\(portValue). Press Ctrl+C to stop.")

    runUntilStopped(seconds: seconds) {
        stream.close()
        print("Receive stopped. Frames received: \(receivedCount)")
    }
}

private func runInjectMouse(_ arguments: [String]) throws {
    let dx = arguments.count >= 2 ? Int32(arguments[1]) ?? 20 : 20
    let dy = arguments.count >= 3 ? Int32(arguments[2]) ?? 0 : 0
    let injector = EventInjector()
    let frame = KmFrame(
        seq: 1,
        timestampUs: nowUs(),
        type: .mouseMoveRel,
        payload: KmPayload.encodeMouseMove(.init(x: dx, y: dy))
    )

    try injector.injectThrowing(frame)
    print("Injected mouse move dx=\(dx), dy=\(dy)")
}

private func runInjectKey(_ arguments: [String]) throws {
    // macOS virtual key code 0x00 is "A" on the US layout.
    let keyCode = arguments.count >= 2 ? UInt16(arguments[1]) ?? 0x00 : 0x00
    let injector = EventInjector()
    let down = KmFrame(
        seq: 1,
        timestampUs: nowUs(),
        type: .keyDown,
        payload: KmPayload.encodeKey(.init(keyCode: keyCode, flags: 0))
    )
    let up = KmFrame(
        seq: 2,
        timestampUs: nowUs(),
        type: .keyUp,
        payload: KmPayload.encodeKey(.init(keyCode: keyCode, flags: 0))
    )

    try injector.injectThrowing(down)
    try injector.injectThrowing(up)
    print("Injected key keyCode=0x\(String(keyCode, radix: 16, uppercase: true))")
}

private func describe(_ frame: KmFrame) -> String {
    let payload = frame.payload.map { String(format: "%02X", $0) }.joined()
    return "seq=\(frame.seq) ts=\(frame.timestampUs) type=\(frame.type) payload=\(payload)"
}

private func nowUs() -> UInt64 {
    UInt64(Date().timeIntervalSince1970 * 1_000_000)
}

private func runUntilStopped(seconds: Double, cleanup: @escaping () -> Void) {
    let signalSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    signal(SIGINT, SIG_IGN)
    signalSource.setEventHandler {
        cleanup()
        CFRunLoopStop(CFRunLoopGetMain())
    }
    signalSource.resume()

    if seconds > 0 {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            cleanup()
            CFRunLoopStop(CFRunLoopGetMain())
        }
    }

    CFRunLoopRun()
}

private func printUsage() {
    print("""
BarelyRealKmSmoke

Usage:
  BarelyRealKmSmoke udp-loopback [port]
      Sends one Heartbeat frame to 127.0.0.1 and verifies it comes back.

  BarelyRealKmSmoke capture [seconds]
      Prints captured CGEventTap mouse/keyboard frames. Requires Accessibility permission.

  BarelyRealKmSmoke send <peerHost> [peerPort] [seconds] [--peer-left|--peer-right] [--remote|--mirror]
      Captures local KM frames and sends them to a peer over raw UDP.
      Default is edge mode: enter Windows after crossing the configured Mac edge.
      Default peer side is right. Use --peer-left when Windows is left of the Mac.
      Use --peer-size WIDTHxHEIGHT if the Windows display is not 1920x1080.
      Use --remote to immediately suppress local Mac input.
      Use --mirror only for debugging.

  BarelyRealKmSmoke receive [localPort] [seconds]
      Receives raw UDP KM frames and injects them locally.

  BarelyRealKmSmoke inject-mouse [dx] [dy]
      Injects one relative mouse move. Default: dx=20 dy=0.

  BarelyRealKmSmoke inject-key [keyCode]
      Injects one key press/release by macOS virtual key code. Default: 0x00 (A on US layout).

Suggested manual smoke:
  swift run BarelyRealKmSmoke udp-loopback
  swift run BarelyRealKmSmoke capture 10
  swift run BarelyRealKmSmoke send <windows-ip> 24801 --peer-left
  swift run BarelyRealKmSmoke receive 24801
  swift run BarelyRealKmSmoke inject-mouse 20 0
  # Focus TextEdit first, then:
  swift run BarelyRealKmSmoke inject-key
""")
}

private enum SmokeError: Error, CustomStringConvertible {
    case invalidPort(UInt16)
    case timeout(String)
    case mismatch(expected: String, actual: String)
    case usage(String)

    var description: String {
        switch self {
        case .invalidPort(let port):
            return "Invalid port: \(port)"
        case .timeout(let message):
            return message
        case .mismatch(let expected, let actual):
            return "Mismatch\nExpected: \(expected)\nActual:   \(actual)"
        case .usage(let message):
            return message
        }
    }
}

private final class RemoteInputGuard {
    private let enabled: Bool
    private var isActive = false
    private var cursorHidden = false
    private var pinnedPoint: CGPoint?

    init(enabled: Bool) {
        self.enabled = enabled
    }

    func start(pinnedAt point: CGPoint) {
        guard enabled, !isActive else { return }

        pinnedPoint = point
        CGWarpMouseCursorPosition(point)
        _ = CGAssociateMouseAndMouseCursorPosition(boolean_t(0))
        if CGDisplayHideCursor(CGMainDisplayID()) == .success {
            cursorHidden = true
        }
        isActive = true
    }

    func maintainPin() {
        guard enabled, isActive, let pinnedPoint else { return }
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

private enum EdgeDirection {
    case left
    case right

    var initialRemoteX: Int32 {
        switch self {
        case .left: return -24
        case .right: return 24
        }
    }

    var enterHint: String {
        switch self {
        case .left:
            return "Move to the left edge of the Mac screen to enter Windows. Move right past the Windows edge to return."
        case .right:
            return "Move to the right edge of the Mac screen to enter Windows. Move left past the Windows edge to return."
        }
    }
}

private struct PeerScreen {
    let width: Int32
    let height: Int32
}

private final class EdgeBridge {
    private let enabled: Bool
    private let direction: EdgeDirection
    private let peerScreen: PeerScreen
    private let stream: UdpKmStream
    private let endpoint: NWEndpoint
    private let guardController: RemoteInputGuard
    private let desktopBounds: CGRect

    private var isRemoteActive: Bool
    private var remoteX: Int32

    init(enabled: Bool, startsActive: Bool, direction: EdgeDirection, peerScreen: PeerScreen, stream: UdpKmStream, endpoint: NWEndpoint) {
        self.enabled = enabled
        self.direction = direction
        self.peerScreen = peerScreen
        self.stream = stream
        self.endpoint = endpoint
        self.isRemoteActive = startsActive
        self.guardController = RemoteInputGuard(enabled: enabled)
        self.desktopBounds = Self.currentDesktopBounds()
        self.remoteX = direction.initialRemoteX

        if startsActive {
            guardController.start(pinnedAt: Self.currentCursorLocation())
        }
    }

    var shouldSuppressLocalEvents: Bool {
        enabled && isRemoteActive
    }

    @discardableResult
    func handle(_ frame: KmFrame) -> Bool {
        guard enabled else {
            stream.send(frame, to: endpoint)
            return true
        }

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

    private func shouldEnterRemote(for frame: KmFrame) -> Bool {
        guard frame.type == .mouseMoveRel,
              let move = try? KmPayload.decodeMouseMove(frame.payload)
        else {
            return false
        }

        let location = CGEvent(source: nil)?.location ?? .zero

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
        print("Entered Windows edge mode at peer x=\(entryPoint.x), y=\(entryPoint.y)")
        fflush(stdout)
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
        CGWarpMouseCursorPosition(CGPoint(x: x, y: CGEvent(source: nil)?.location.y ?? desktopBounds.midY))
        print("Returned to Mac edge mode")
        fflush(stdout)
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

private func parsePeerScreen(_ arguments: [String]) -> PeerScreen? {
    guard let sizeIndex = arguments.firstIndex(of: "--peer-size"),
          arguments.indices.contains(sizeIndex + 1)
    else {
        return nil
    }

    let parts = arguments[sizeIndex + 1]
        .lowercased()
        .split(separator: "x", maxSplits: 1)
        .compactMap { Int32($0) }

    guard parts.count == 2, parts[0] > 0, parts[1] > 0 else {
        return nil
    }

    return PeerScreen(width: parts[0], height: parts[1])
}
