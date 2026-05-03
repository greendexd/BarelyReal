import Foundation

/// Tracks "are KM frames flowing" on the receive side.
///
/// Wires:
///  - call `noteFrame()` on every successfully decoded inbound frame
///  - subscribe to `onLinkLost` / `onLinkRecovered`
///
/// Default thresholds match the BRP spec: 1500 ms = link lost, 5000 ms = optionally lock screen.
public final class KmLinkMonitor {
    public struct Configuration {
        public var linkLostAfter: TimeInterval
        public var lockScreenAfter: TimeInterval
        public var pollInterval: TimeInterval

        public init(linkLostAfter: TimeInterval = 1.5, lockScreenAfter: TimeInterval = 5.0, pollInterval: TimeInterval = 0.1) {
            self.linkLostAfter = linkLostAfter
            self.lockScreenAfter = lockScreenAfter
            self.pollInterval = pollInterval
        }
    }

    public enum Event: Equatable {
        case linkLost(silentFor: TimeInterval)
        case linkRecovered
        case shouldLockScreen
    }

    public var onEvent: ((Event) -> Void)?

    public private(set) var isActive = false
    public private(set) var isLinkUp = false

    private let configuration: Configuration
    private let queue: DispatchQueue
    private var timer: DispatchSourceTimer?
    private var lastFrameAt: Date?
    private var lockTriggered = false

    public init(configuration: Configuration = Configuration(),
                queue: DispatchQueue = DispatchQueue(label: "com.barelyreal.km-link-monitor")) {
        self.configuration = configuration
        self.queue = queue
    }

    public func start() {
        stop()
        isActive = true
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + configuration.pollInterval,
                       repeating: configuration.pollInterval)
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        self.timer = timer
    }

    public func stop() {
        timer?.cancel()
        timer = nil
        isActive = false
        isLinkUp = false
        lastFrameAt = nil
        lockTriggered = false
    }

    public func noteFrame() {
        let now = Date()
        queue.async { [weak self] in
            guard let self else { return }
            self.lastFrameAt = now
            self.lockTriggered = false
            if !self.isLinkUp {
                self.isLinkUp = true
                self.onEvent?(.linkRecovered)
            }
        }
    }

    private func tick() {
        guard isActive, let lastFrameAt else { return }
        let silent = Date().timeIntervalSince(lastFrameAt)

        if isLinkUp, silent >= configuration.linkLostAfter {
            isLinkUp = false
            onEvent?(.linkLost(silentFor: silent))
        }

        if !lockTriggered, silent >= configuration.lockScreenAfter {
            lockTriggered = true
            onEvent?(.shouldLockScreen)
        }
    }
}
