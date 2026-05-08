import AppKit
import BarelyRealCore
import CoreGraphics
import Foundation
import Network

/// Receives KM frames from a remote peer (e.g. Windows) and injects them locally.
final class MacReceiverSession {
    enum ReceiverError: LocalizedError {
        case missingAllowedPeer

        var errorDescription: String? {
            switch self {
            case .missingAllowedPeer:
                "Windows IP is required before starting Windows → Mac input."
            }
        }
    }

    private let kmPort: UInt16
    private let peerFilter: UdpPeerFilter
    private let kmSharedSecret: String
    private let log: (String) -> Void

    private let stream = UdpKmStream()
    private let injector = EventInjector()
    private let linkMonitor = KmLinkMonitor()

    private(set) var receivedCount = 0
    private(set) var isLinkUp = false
    private var droppedCount = 0
    private var lastDropLog = Date.distantPast
    var lockOnDisconnect = false
    var onLinkChange: ((Bool) -> Void)?

    init(kmPort: UInt16, allowedPeerHost: String, kmSharedSecret: String, log: @escaping (String) -> Void) {
        self.kmPort = kmPort
        self.peerFilter = UdpPeerFilter(expectedHost: allowedPeerHost)
        self.kmSharedSecret = kmSharedSecret
        self.log = log
    }

    func start() throws {
        guard peerFilter.isActive else {
            throw ReceiverError.missingAllowedPeer
        }

        stream.onFrameFrom = { [weak self] frame, endpoint in
            self?.handle(frame, remote: endpoint)
        }
        stream.onDrop = { [weak self] message in
            self?.noteDroppedFrame(message)
        }
        stream.authenticationSecret = kmSharedSecret
        try stream.bind(localPort: kmPort)

        linkMonitor.onEvent = { [weak self] event in
            guard let self else { return }
            switch event {
            case .linkRecovered:
                self.isLinkUp = true
                self.log("KM link up.")
                DispatchQueue.main.async { self.onLinkChange?(true) }

            case .linkLost(let silent):
                self.isLinkUp = false
                self.log(String(format: "KM link lost (silent for %.0f ms).", silent * 1000))
                DispatchQueue.main.async { self.onLinkChange?(false) }

            case .shouldLockScreen:
                if self.lockOnDisconnect {
                    self.log("Locking display (long silence).")
                    self.lockDisplay()
                }
            }
        }
        linkMonitor.start()

        let auth = UdpKmAuthenticator(sharedSecret: kmSharedSecret) == nil ? "auth off" : "auth on"
        log("Receiving KM frames on UDP :\(kmPort) from trusted peer \(peerFilter.expectedHost) (\(auth))")
    }

    func stop() {
        linkMonitor.stop()
        stream.close()
        isLinkUp = false
    }

    private func handle(_ frame: KmFrame, remote endpoint: NWEndpoint) {
        guard let remoteHost = remoteHost(from: endpoint),
              peerFilter.allows(remoteHost: remoteHost)
        else {
            noteDroppedFrame(from: endpoint)
            return
        }

        linkMonitor.noteFrame()
        if frame.type == .heartbeat || frame.type == .clockSync {
            return
        }

        do {
            try injector.injectThrowing(frame)
        } catch {
            log("inject failed: \(error)")
        }

        receivedCount += 1
        if receivedCount <= 10 || receivedCount % 500 == 0 {
            log("received seq=\(frame.seq) type=\(frame.type)")
        }
    }

    private func remoteHost(from endpoint: NWEndpoint) -> String? {
        guard case let .hostPort(host, _) = endpoint else {
            return nil
        }

        switch host {
        case .name(let name, _):
            return name
        case .ipv4(let address):
            return "\(address)"
        case .ipv6(let address):
            return "\(address)"
        @unknown default:
            return "\(host)"
        }
    }

    private func noteDroppedFrame(from endpoint: NWEndpoint) {
        noteDroppedFrame("Dropped KM frame from untrusted UDP peer \(endpoint). Expected \(peerFilter.expectedHost).")
    }

    private func noteDroppedFrame(_ message: String) {
        droppedCount += 1
        let now = Date()
        guard droppedCount <= 3 || now.timeIntervalSince(lastDropLog) > 10 else {
            return
        }
        lastDropLog = now
        log(message)
    }

    private func lockDisplay() {
        // The "official" macOS API to lock the screen requires private SPI. Use pmset displaysleepnow
        // which puts the display to sleep — locking happens if "Require password after sleep" is on
        // (default since macOS Catalina).
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["displaysleepnow"]
        do {
            try process.run()
        } catch {
            log("pmset displaysleepnow failed: \(error)")
        }
    }
}
