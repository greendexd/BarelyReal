import AppKit
import BarelyRealCore
import CryptoKit
import Foundation
import Network

final class ClipboardTextSession {
    private enum ClipboardKind: UInt8 {
        case text = 1
        case imagePNG = 2
        case fileBundle = 3
    }

    private struct ClipboardItem {
        let kind: ClipboardKind
        let payload: Data

        var packetBody: Data {
            var data = Data(capacity: 1 + payload.count)
            data.append(kind.rawValue)
            data.append(payload)
            return data
        }

        var hash: String {
            var data = Data(capacity: 1 + payload.count)
            data.append(kind.rawValue)
            data.append(payload)
            return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }

        var logLabel: String {
            switch kind {
            case .text:
                return "text/plain \(payload.count) bytes hash=\(hash.prefix(12))"
            case .imagePNG:
                return "image/png \(payload.count) bytes hash=\(hash.prefix(12))"
            case .fileBundle:
                if let bundle = try? ClipboardFileBundleCodec.decode(payload) {
                    return "files (\(bundle.files.count)) \(payload.count) bytes hash=\(hash.prefix(12))"
                }
                return "files \(payload.count) bytes hash=\(hash.prefix(12))"
            }
        }

        static func text(_ text: String) -> ClipboardItem {
            ClipboardItem(kind: .text, payload: Data(text.utf8))
        }

        static func imagePNG(_ data: Data) -> ClipboardItem {
            ClipboardItem(kind: .imagePNG, payload: data)
        }

        static func fileBundle(_ bundle: ClipboardFileBundle) -> ClipboardItem {
            ClipboardItem(kind: .fileBundle, payload: ClipboardFileBundleCodec.encode(bundle))
        }
    }

    private static let maxPayloadBytes = 220_000_000
    private static let historyMaxBytesPerFormat = 1_500_000

    var onHistoryEntry: ((ClipboardEntry) -> Void)?

    private let peerHost: String
    private let port: UInt16
    private let log: (String) -> Void
    private let pasteboard = NSPasteboard.general
    private let queue = DispatchQueue(label: "BarelyReal.App.ClipboardSession")

    private var listener: NWListener?
    private var timer: DispatchSourceTimer?
    private var lastChangeCount: Int
    private var lastSentHash: String?
    private var lastAppliedRemoteHash: String?

    init(peerHost: String, port: UInt16, log: @escaping (String) -> Void) {
        self.peerHost = peerHost
        self.port = port
        self.log = log
        self.lastChangeCount = pasteboard.changeCount
    }

    func start() throws {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            throw ClipboardSessionError.invalidPort(port)
        }

        let listener = try NWListener(using: .tcp, on: endpointPort)
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.start(queue: queue)
        self.listener = listener

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + .milliseconds(200), repeating: .milliseconds(200))
        timer.setEventHandler { [weak self] in
            self?.pollLocalClipboard()
        }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
        listener?.cancel()
        listener = nil
    }

    func sendTestText() {
        send(.text("BarelyReal clipboard text test \(Self.timestampFormatter.string(from: Date()))"))
    }

    func sendTestImage() {
        guard let data = Self.makeTestPNG() else {
            log("Clipboard image test failed: could not render PNG")
            return
        }

        send(.imagePNG(data))
    }

    func sendTestFile() {
        let stamp = Self.timestampFormatter.string(from: Date())
        let contents = """
        BarelyReal file clipboard test
        Sent at \(stamp)
        """
        let file = ClipboardFile(
            name: "barelyreal-file-test.txt",
            bytes: Data(contents.utf8)
        )
        send(.fileBundle(ClipboardFileBundle(files: [file])))
    }

    private func pollLocalClipboard() {
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount

        guard let item = readLocalClipboardItem() else { return }
        guard item.hash != lastAppliedRemoteHash, item.hash != lastSentHash else { return }

        send(item)
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
            guard length > 1, length <= Self.maxPayloadBytes else {
                self.log("Clipboard receive rejected invalid length \(length)")
                connection.cancel()
                return
            }

            self.receiveBody(length: Int(length), on: connection)
        }
    }

    private func receiveBody(length: Int, on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] data, _, _, _ in
            defer { connection.cancel() }
            guard let self, let data, data.count == length else { return }
            guard let kind = ClipboardKind(rawValue: data[data.startIndex]) else {
                self.log("Clipboard receive rejected unknown kind \(data[data.startIndex])")
                return
            }

            let payloadStart = data.index(after: data.startIndex)
            let payload = Data(data[payloadStart..<data.endIndex])
            self.applyRemote(ClipboardItem(kind: kind, payload: payload))
        }
    }

    private func applyRemote(_ item: ClipboardItem) {
        DispatchQueue.main.async {
            if self.readLocalClipboardItem()?.hash == item.hash {
                self.lastAppliedRemoteHash = item.hash
                return
            }

            switch item.kind {
            case .text:
                guard let text = String(data: item.payload, encoding: .utf8) else {
                    self.log("Clipboard received invalid UTF-8")
                    return
                }
                self.pasteboard.clearContents()
                self.pasteboard.setString(text, forType: .string)

            case .imagePNG:
                self.pasteboard.clearContents()
                self.pasteboard.setData(item.payload, forType: .png)
                if let image = NSImage(data: item.payload),
                   let tiff = image.tiffRepresentation {
                    self.pasteboard.setData(tiff, forType: .tiff)
                }

            case .fileBundle:
                guard let bundle = try? ClipboardFileBundleCodec.decode(item.payload) else {
                    self.log("Clipboard received malformed file bundle")
                    return
                }
                self.applyFileBundle(bundle)
            }

            self.lastChangeCount = self.pasteboard.changeCount
            self.lastAppliedRemoteHash = item.hash
            self.log("Clipboard received: \(item.logLabel)")
            self.recordHistory(item)
        }
    }

    private func recordHistory(_ item: ClipboardItem) {
        let formatKey: String
        switch item.kind {
        case .text: formatKey = "text/plain"
        case .imagePNG: formatKey = "image/png"
        case .fileBundle: formatKey = "application/x-barelyreal-files"
        }
        let bytes = item.payload.count > Self.historyMaxBytesPerFormat
            ? Data(item.payload.prefix(Self.historyMaxBytesPerFormat))
            : item.payload
        let id = UInt64(Date().timeIntervalSince1970 * 1000)
        let hashData = SHA256.hash(data: item.packetBody).withUnsafeBytes { Data($0) }
        let entry = ClipboardEntry(
            id: id,
            formats: [formatKey: bytes],
            contentHash: hashData
        )
        DispatchQueue.main.async { [weak self] in
            self?.onHistoryEntry?(entry)
        }
    }

    private func applyFileBundle(_ bundle: ClipboardFileBundle) {
        guard !bundle.files.isEmpty else { return }

        let downloads: URL
        if let dir = try? FileManager.default.url(for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: true) {
            downloads = dir
        } else {
            downloads = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads", isDirectory: true)
        }

        let stamp = Self.fileStampFormatter.string(from: Date())
        let target = downloads.appendingPathComponent("BarelyReal", isDirectory: true)
            .appendingPathComponent(stamp, isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        } catch {
            log("Clipboard file save failed: cannot create \(target.path): \(error)")
            return
        }

        var urls: [URL] = []
        urls.reserveCapacity(bundle.files.count)
        for file in bundle.files {
            let dest = uniqueDestination(in: target, for: file.name)
            do {
                try file.bytes.write(to: dest, options: .atomic)
                urls.append(dest)
            } catch {
                log("Clipboard file write failed for \(file.name): \(error)")
            }
        }

        guard !urls.isEmpty else { return }

        pasteboard.clearContents()
        pasteboard.writeObjects(urls as [NSURL])
    }

    private func uniqueDestination(in directory: URL, for proposedName: String) -> URL {
        var candidate = directory.appendingPathComponent(proposedName)
        guard FileManager.default.fileExists(atPath: candidate.path) else {
            return candidate
        }

        let base = (proposedName as NSString).deletingPathExtension
        let ext = (proposedName as NSString).pathExtension
        var counter = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            counter += 1
            let newName = ext.isEmpty ? "\(base) (\(counter))" : "\(base) (\(counter)).\(ext)"
            candidate = directory.appendingPathComponent(newName)
            if counter > 999 { break }
        }
        return candidate
    }

    private static let fileStampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    private func readLocalClipboardItem() -> ClipboardItem? {
        if let bundle = readLocalFileBundle() {
            return .fileBundle(bundle)
        }

        if let png = pasteboard.data(forType: .png), !png.isEmpty {
            return .imagePNG(png)
        }

        if let tiff = pasteboard.data(forType: .tiff),
           let image = NSImage(data: tiff),
           let png = Self.pngData(from: image),
           !png.isEmpty {
            return .imagePNG(png)
        }

        if let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let image = images.first,
           let png = Self.pngData(from: image),
           !png.isEmpty {
            return .imagePNG(png)
        }

        guard let text = pasteboard.string(forType: .string), !text.isEmpty else {
            return nil
        }

        return .text(text)
    }

    private func readLocalFileBundle() -> ClipboardFileBundle? {
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
              !urls.isEmpty
        else {
            return nil
        }

        var files: [ClipboardFile] = []
        var totalBytes: UInt64 = 0
        var skippedDirs = 0
        var oversize: [String] = []
        let limitTotal = ClipboardFileBundleCodec.maxTotalBytes
        let limitFile = ClipboardFileBundleCodec.maxFileBytes
        let limitCount = ClipboardFileBundleCodec.maxFiles

        for url in urls.prefix(limitCount) {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                continue
            }
            if isDirectory.boolValue {
                skippedDirs += 1
                continue
            }

            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            let size = (attrs?[.size] as? NSNumber)?.uint64Value ?? 0
            if size > limitFile {
                oversize.append(url.lastPathComponent)
                continue
            }
            if totalBytes &+ size > limitTotal {
                oversize.append(url.lastPathComponent)
                continue
            }

            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
                continue
            }
            guard let safeName = ClipboardFileBundleCodec.sanitizeName(url.lastPathComponent) else {
                continue
            }

            totalBytes &+= UInt64(data.count)
            files.append(ClipboardFile(name: safeName, bytes: data))
        }

        if files.isEmpty {
            if skippedDirs > 0 {
                log("Clipboard file send skipped: \(skippedDirs) directory entries (folders not supported in MVP)")
            }
            if !oversize.isEmpty {
                log("Clipboard file send skipped (too big): \(oversize.joined(separator: ", "))")
            }
            return nil
        }

        if skippedDirs > 0 {
            log("Clipboard file send: skipped \(skippedDirs) directory entries")
        }
        if !oversize.isEmpty {
            log("Clipboard file send: skipped oversize \(oversize.joined(separator: ", "))")
        }

        return ClipboardFileBundle(files: files)
    }

    private func send(_ item: ClipboardItem) {
        guard item.payload.count <= Self.maxPayloadBytes,
              let endpointPort = NWEndpoint.Port(rawValue: port)
        else {
            log("Clipboard send rejected oversized payload: \(item.payload.count) bytes")
            return
        }

        lastSentHash = item.hash
        recordHistory(item)

        let connection = NWConnection(host: NWEndpoint.Host(peerHost), port: endpointPort, using: .tcp)
        let body = item.packetBody
        var packet = Data(capacity: 4 + body.count)
        packet.appendLE(UInt32(body.count))
        packet.append(body)

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                connection.send(content: packet, completion: .contentProcessed { error in
                    if let error {
                        self?.log("Clipboard send failed: \(error)")
                    } else {
                        self?.log("Clipboard sent: \(item.logLabel)")
                    }
                    connection.cancel()
                })
            case .waiting(let error):
                self?.log("Clipboard waiting: \(Self.describe(error))")
            case .failed(let error):
                self?.log("Clipboard failed: \(Self.describe(error))")
                connection.cancel()
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff)
        else {
            return nil
        }

        return bitmap.representation(using: .png, properties: [:])
    }

    private static func makeTestPNG() -> Data? {
        let image = NSImage(size: NSSize(width: 360, height: 180))
        image.lockFocus()

        NSColor.systemBlue.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 360, height: 180)).fill()

        NSColor.white.setFill()
        NSBezierPath(roundedRect: NSRect(x: 24, y: 24, width: 312, height: 132), xRadius: 14, yRadius: 14).fill()

        let title = "BarelyReal"
        let subtitle = "PNG clipboard test \(timestampFormatter.string(from: Date()))"
        title.draw(
            at: NSPoint(x: 48, y: 100),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 34, weight: .bold),
                .foregroundColor: NSColor.black,
            ]
        )
        subtitle.draw(
            at: NSPoint(x: 50, y: 68),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 17, weight: .medium),
                .foregroundColor: NSColor.darkGray,
            ]
        )

        image.unlockFocus()
        return pngData(from: image)
    }

    private static func describe(_ error: NWError) -> String {
        switch error {
        case .posix(let code):
            return code == .ECONNREFUSED
                ? "Windows clipboard port refused. Start Windows receiver with clipboard enabled."
                : "network error \(code.rawValue)"
        case .dns(let code):
            return "DNS error \(code)"
        case .tls(let code):
            return "TLS error \(code)"
        case .wifiAware(let code):
            return "Wi-Fi Aware error \(code)"
        @unknown default:
            return "\(error)"
        }
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

enum ClipboardSessionError: Error, CustomStringConvertible {
    case invalidPort(UInt16)

    var description: String {
        switch self {
        case .invalidPort(let port): "Invalid clipboard port: \(port)"
        }
    }
}
