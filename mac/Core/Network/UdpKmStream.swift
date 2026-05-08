import Foundation
import Network

/// UDP socket carrying encoded KmFrame events.
/// TODO: wrap frames in AEAD once TlsSession exposes exporter-derived key material.
public final class UdpKmStream {
    public enum StreamError: Error, Equatable {
        case invalidPort(UInt16)
    }

    public var onFrame: ((KmFrame) -> Void)?
    public var onFrameFrom: ((KmFrame, NWEndpoint) -> Void)?

    private let queue: DispatchQueue
    private var listener: NWListener?
    private var connections: [String: NWConnection] = [:]

    public init(queue: DispatchQueue = DispatchQueue(label: "com.barelyreal.udp-km")) {
        self.queue = queue
    }

    public func bind(localPort: UInt16) throws {
        guard let port = NWEndpoint.Port(rawValue: localPort) else {
            throw StreamError.invalidPort(localPort)
        }

        close()

        let listener = try NWListener(using: .udp, on: port)
        listener.newConnectionHandler = { [weak self] connection in
            self?.startInbound(connection)
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    public func send(_ frame: KmFrame, to peer: NWEndpoint) {
        let payload = KmFrameCodec.encode(frame)
        queue.async { [weak self] in
            guard let self else { return }
            let connection = self.connection(to: peer)
            connection.send(content: payload, completion: .contentProcessed { _ in })
        }
    }

    public func close() {
        listener?.cancel()
        listener = nil

        for connection in connections.values {
            connection.cancel()
        }
        connections.removeAll()
    }

    private func startInbound(_ connection: NWConnection) {
        let key = String(describing: connection.endpoint)
        connections[key] = connection
        connection.start(queue: queue)
        receiveNext(on: connection)
    }

    private func receiveNext(on connection: NWConnection) {
        connection.receiveMessage { [weak self, weak connection] content, _, _, error in
            guard let self, let connection else { return }

            if let content {
                do {
                    let frame = try KmFrameCodec.decode(content)
                    self.onFrame?(frame)
                    self.onFrameFrom?(frame, connection.endpoint)
                } catch {
                    // Malformed UDP datagrams are dropped. Control channel will own reconnect policy.
                }
            }

            if error == nil {
                self.receiveNext(on: connection)
            }
        }
    }

    private func connection(to peer: NWEndpoint) -> NWConnection {
        let key = String(describing: peer)
        if let connection = connections[key] {
            return connection
        }

        let connection = NWConnection(to: peer, using: .udp)
        connections[key] = connection
        connection.start(queue: queue)
        return connection
    }
}
