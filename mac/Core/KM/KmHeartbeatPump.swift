import Foundation

/// Drives a periodic Heartbeat frame on a KM stream when the user is idle.
///
/// Whenever a real frame is sent, call `noteFrameSent()` so the pump can defer the next
/// heartbeat. If `interval` elapses without a real frame, the pump emits a Heartbeat via
/// `send`. Default interval = 50 ms per BRP § Heartbeat & timeouts.
public final class KmHeartbeatPump {
    public struct Configuration {
        public var interval: TimeInterval

        public init(interval: TimeInterval = 0.05) {
            self.interval = interval
        }
    }

    private let configuration: Configuration
    private let queue: DispatchQueue
    private let send: (KmFrame) -> Void
    private let nextSeq: () -> UInt32

    private var timer: DispatchSourceTimer?
    private var lastFrameSentAt: Date = Date(timeIntervalSince1970: 0)

    public init(configuration: Configuration = Configuration(),
                queue: DispatchQueue = DispatchQueue(label: "com.barelyreal.km-heartbeat"),
                nextSeq: @escaping () -> UInt32,
                send: @escaping (KmFrame) -> Void) {
        self.configuration = configuration
        self.queue = queue
        self.nextSeq = nextSeq
        self.send = send
    }

    public func start() {
        stop()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + configuration.interval,
                       repeating: configuration.interval)
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        self.timer = timer
    }

    public func stop() {
        timer?.cancel()
        timer = nil
    }

    public func noteFrameSent() {
        let now = Date()
        queue.async { [weak self] in
            self?.lastFrameSentAt = now
        }
    }

    private func tick() {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastFrameSentAt)
        guard elapsed >= configuration.interval else { return }
        let frame = KmFrame(
            seq: nextSeq(),
            timestampUs: UInt64(now.timeIntervalSince1970 * 1_000_000),
            type: .heartbeat
        )
        lastFrameSentAt = now
        send(frame)
    }
}
