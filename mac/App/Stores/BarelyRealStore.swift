import ApplicationServices
import AppKit
import BarelyRealCore
import Foundation
import IOKit.hid

enum MacKmMode: String, CaseIterable, Identifiable, Codable {
    case sendToWindows
    case receiveFromWindows

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sendToWindows: "Mac → Windows (Mac is keyboard host)"
        case .receiveFromWindows: "Windows → Mac (Windows is keyboard host)"
        }
    }
}

@MainActor
final class BarelyRealStore: ObservableObject {
    @Published private(set) var kmRunning = false
    @Published private(set) var clipboardRunning = false
    @Published private(set) var receiverLinkUp = false
    @Published private(set) var lastError: String?
    @Published private(set) var logLines: [String] = []
    @Published private(set) var clipboardEntries: [ClipboardEntry] = []
    @Published var permissionRefreshToken = UUID()
    @Published var lockOnDisconnect = false

    private let history = ClipboardHistory()
    private var kmSession: MacKmSession?
    private var receiverSession: MacReceiverSession?
    private var clipboardSession: ClipboardTextSession?

    var accessibilityGranted: Bool {
        _ = permissionRefreshToken
        return AXIsProcessTrusted()
    }

    var inputMonitoringGranted: Bool {
        _ = permissionRefreshToken
        return IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    func start(settings: ConnectionSettings) {
        lastError = nil

        if !accessibilityGranted {
            appendLog("Accessibility permission is missing; KM capture may not start.")
        }
        if !inputMonitoringGranted {
            appendLog("Input Monitoring permission is missing; keyboard capture may fail.")
        }

        switch settings.mode {
        case .sendToWindows:
            startKm(settings: settings)
        case .receiveFromWindows:
            startReceiver(settings: settings)
        }
        startClipboard(settings: settings)
    }

    func stop() {
        kmSession?.stop()
        kmSession = nil

        receiverSession?.stop()
        receiverSession = nil
        receiverLinkUp = false

        kmRunning = false

        clipboardSession?.stop()
        clipboardSession = nil
        clipboardRunning = false

        appendLog("Stopped")
    }

    func sendClipboardTest(settings: ConnectionSettings) {
        if clipboardSession == nil {
            startClipboard(settings: settings)
        }

        clipboardSession?.sendTestText()
        appendLog("Clipboard text test sent")
    }

    func sendClipboardImageTest(settings: ConnectionSettings) {
        if clipboardSession == nil {
            startClipboard(settings: settings)
        }

        clipboardSession?.sendTestImage()
        appendLog("Clipboard image test sent")
    }

    func sendClipboardFileTest(settings: ConnectionSettings) {
        if clipboardSession == nil {
            startClipboard(settings: settings)
        }

        clipboardSession?.sendTestFile()
        appendLog("Clipboard file test sent")
    }

    func sendWakeOnLan(macAddress: String, broadcastHost: String) {
        do {
            try WakeOnLan.send(macAddress: macAddress, broadcastHost: broadcastHost)
            appendLog("Wake-on-LAN sent to \(macAddress) via \(broadcastHost):9")
        } catch {
            lastError = "Wake-on-LAN failed: \(error)"
            appendLog(lastError ?? "Wake-on-LAN failed")
        }
    }

    func refreshPermissions() {
        permissionRefreshToken = UUID()
    }

    func openAccessibilitySettings() {
        openSystemSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    func openInputMonitoringSettings() {
        openSystemSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    func requestInputMonitoring() {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        refreshPermissions()
    }

    func resetBarelyRealPermissions() {
        runTccutilReset(service: "Accessibility")
        runTccutilReset(service: "ListenEvent")
        refreshPermissions()
        appendLog("Reset BarelyReal permissions. Enable Accessibility and Input Monitoring again.")
        openAccessibilitySettings()
    }

    private func startReceiver(settings: ConnectionSettings) {
        receiverSession?.stop()
        let session = MacReceiverSession(kmPort: UInt16(settings.kmPort)) { [weak self] message in
            Task { @MainActor in self?.appendLog(message) }
        }
        session.lockOnDisconnect = lockOnDisconnect
        session.onLinkChange = { [weak self] linkUp in
            Task { @MainActor in self?.receiverLinkUp = linkUp }
        }
        do {
            try session.start()
            receiverSession = session
            kmRunning = true
            appendLog("Receiver started on UDP :\(settings.kmPort). Lock-on-disconnect: \(lockOnDisconnect ? "on" : "off")")
        } catch {
            kmRunning = false
            lastError = "Receiver start failed: \(error)"
            appendLog(lastError ?? "Receiver start failed")
        }
    }

    func setLockOnDisconnect(_ enabled: Bool) {
        lockOnDisconnect = enabled
        receiverSession?.lockOnDisconnect = enabled
    }

    func wakePeer(macAddress: String, broadcastHost: String) {
        do {
            try WakeOnLan.send(macAddress: macAddress, broadcastHost: broadcastHost)
            appendLog("Wake-on-LAN packet sent to \(macAddress) via \(broadcastHost)")
        } catch {
            lastError = "WoL failed: \(error)"
            appendLog(lastError ?? "WoL failed")
        }
    }

    private func startKm(settings: ConnectionSettings) {
        kmSession?.stop()

        do {
            let session = MacKmSession(
                peerHost: settings.peerHost,
                peerPort: UInt16(settings.kmPort),
                direction: settings.peerSide.direction,
                peerScreen: PeerScreen(width: Int32(settings.peerWidth), height: Int32(settings.peerHeight)),
                scrollSpeed: settings.scrollSpeed
            ) { [weak self] message in
                Task { @MainActor in self?.appendLog(message) }
            }

            try session.start()
            kmSession = session
            kmRunning = true
            appendLog("KM started: \(settings.peerHost):\(settings.kmPort), \(settings.peerSide.title), scroll \(settings.scrollSpeed)/20")
        } catch {
            kmRunning = false
            lastError = "KM start failed: \(error)"
            appendLog(lastError ?? "KM start failed")
        }
    }

    private func startClipboard(settings: ConnectionSettings) {
        clipboardSession?.stop()

        do {
            let session = ClipboardTextSession(
                peerHost: settings.peerHost,
                port: UInt16(settings.clipboardPort)
            ) { [weak self] message in
                Task { @MainActor in self?.appendLog(message) }
            }
            session.onHistoryEntry = { [weak self] entry in
                Task { @MainActor in self?.recordClipboardEntry(entry) }
            }

            try session.start()
            clipboardSession = session
            clipboardRunning = true
            // Seed UI from disk so the user sees prior items.
            clipboardEntries = history.recent()
            appendLog("Clipboard started: \(settings.peerHost):\(settings.clipboardPort)")
        } catch {
            clipboardRunning = false
            lastError = "Clipboard start failed: \(error)"
            appendLog(lastError ?? "Clipboard start failed")
        }
    }

    private func recordClipboardEntry(_ entry: ClipboardEntry) {
        history.append(entry)
        clipboardEntries = history.recent()
    }

    func loadClipboardHistory() {
        clipboardEntries = history.recent()
    }

    private func appendLog(_ message: String) {
        let timestamp = Self.timeFormatter.string(from: Date())
        logLines.append("[\(timestamp)] \(message)")
        if logLines.count > 80 {
            logLines.removeFirst(logLines.count - 80)
        }
    }

    private func openSystemSettings(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    private func runTccutilReset(service: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", service, "local.barelyreal.mac"]
        try? process.run()
        process.waitUntilExit()
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

struct ConnectionSettings {
    var peerHost: String
    var kmPort: Int
    var clipboardPort: Int
    var peerSide: PeerSide
    var peerWidth: Int
    var peerHeight: Int
    var scrollSpeed: Int
    var mode: MacKmMode = .sendToWindows
}
