import Foundation
import Network

public final class DevControlSession: @unchecked Sendable {
    public enum ControlError: Error, Equatable {
        case invalidPort(UInt16)
    }

    public var onScreenAnnounce: ((ScreenAnnouncement) -> Void)?
    public var onLayoutSync: ((LayoutSyncMessage) -> Void)?
    public var onLog: ((String) -> Void)?

    private let queue: DispatchQueue
    private var listener: NWListener?
    private var peerHost: String?
    private var peerPort: UInt16

    public init(queue: DispatchQueue = DispatchQueue(label: "com.barelyreal.dev-control")) {
        self.queue = queue
        self.peerPort = 24_800
    }

    public func start(localPort: UInt16 = 24_800, peerHost: String?, peerPort: UInt16 = 24_800) throws {
        close()
        self.peerHost = peerHost?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.peerPort = peerPort

        guard let port = NWEndpoint.Port(rawValue: localPort) else {
            throw ControlError.invalidPort(localPort)
        }

        let listener = try NWListener(using: .tcp, on: port)
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.start(queue: queue)
        self.listener = listener
        onLog?("Control listening on TCP :\(localPort)")
    }

    public func close() {
        listener?.cancel()
        listener = nil
    }

    public func sendHello(_ hello: HelloMessage) {
        sendJSON(.hello, hello)
    }

    public func sendScreenAnnounce(_ announcement: ScreenAnnouncement) {
        sendJSON(.screenAnnounce, announcement)
    }

    public func sendLayoutSync(_ layout: LayoutSyncMessage) {
        sendJSON(.layoutSync, layout)
    }

    public func sendKeepAlive() {
        send(.init(type: .keepAlive, body: Data("{}".utf8)))
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveHeader(on: connection)
    }

    private func receiveHeader(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, _, error in
            guard let self else { return }
            guard error == nil, let data, data.count == 4 else {
                connection.cancel()
                return
            }
            let length: UInt32 = data.readLE(at: 0)
            guard length >= 1, length <= ControlFrameCodec.maxBodySize + 1 else {
                self.onLog?("Control rejected invalid length \(length)")
                connection.cancel()
                return
            }
            self.receiveBody(length: Int(length), on: connection)
        }
    }

    private func receiveBody(length: Int, on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] body, _, _, _ in
            defer { connection.cancel() }
            guard let self, let body, body.count == length else { return }
            var packet = Data(capacity: 4 + body.count)
            packet.appendLE(UInt32(body.count))
            packet.append(body)
            do {
                let decoded = try ControlFrameCodec.decode(packet).frame
                self.handle(decoded)
            } catch {
                self.onLog?("Control decode failed: \(error)")
            }
        }
    }

    private func handle(_ frame: ControlFrame) {
        do {
            switch frame.type {
            case .screenAnnounce:
                onScreenAnnounce?(try JSONDecoder().decode(ScreenAnnouncement.self, from: frame.body))
            case .layoutSync:
                onLayoutSync?(try JSONDecoder().decode(LayoutSyncMessage.self, from: frame.body))
            case .hello:
                let hello = try JSONDecoder().decode(HelloMessage.self, from: frame.body)
                let announcement = ScreenAnnouncement(peerId: hello.os.lowercased().contains("win") ? "windows" : "mac", screens: hello.screens)
                onScreenAnnounce?(announcement)
            case .keepAlive:
                break
            default:
                onLog?("Control ignored \(frame.type)")
            }
        } catch {
            onLog?("Control message parse failed: \(error)")
        }
    }

    private func sendJSON<T: Encodable>(_ type: ControlType, _ value: T) {
        do {
            let data = try JSONEncoder().encode(value)
            send(.init(type: type, body: data))
        } catch {
            onLog?("Control encode failed: \(error)")
        }
    }

    private func send(_ frame: ControlFrame) {
        guard let peerHost, !peerHost.isEmpty,
              let port = NWEndpoint.Port(rawValue: peerPort)
        else { return }
        let payload = ControlFrameCodec.encode(frame)
        let connection = NWConnection(to: .hostPort(host: .name(peerHost, nil), port: port), using: .tcp)
        connection.start(queue: queue)
        connection.send(content: payload, completion: .contentProcessed { [weak self] error in
            if let error {
                self?.onLog?("Control send failed: \(error)")
            }
            connection.cancel()
        })
    }
}
