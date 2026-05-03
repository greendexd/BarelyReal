import AppKit
import BarelyRealCore
import CoreGraphics
import Foundation
import Network

/// Receives KM frames from a remote peer (e.g. Windows) and injects them locally.
final class MacReceiverSession {
    private let kmPort: UInt16
    private let log: (String) -> Void

    private let stream = UdpKmStream()
    private let injector = EventInjector()
    private let linkMonitor = KmLinkMonitor()

    private(set) var receivedCount = 0
    private(set) var isLinkUp = false
    var lockOnDisconnect = false
    var onLinkChange: ((Bool) -> Void)?

    init(kmPort: UInt16, log: @escaping (String) -> Void) {
        self.kmPort = kmPort
        self.log = log
    }

    func start() throws {
        stream.onFrame = { [weak self] frame in
            self?.handle(frame)
        }
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

        log("Receiving KM frames on UDP :\(kmPort)")
    }

    func stop() {
        linkMonitor.stop()
        stream.close()
        isLinkUp = false
    }

    private func handle(_ frame: KmFrame) {
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
