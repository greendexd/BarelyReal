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
    @Published private(set) var localDisplays: [DisplayInfo] = []
    @Published private(set) var remoteDisplays: [DisplayInfo] = []
    @Published private(set) var virtualLayout = Layout(screens: [])
    @Published private(set) var controlRunning = false
    @Published private(set) var remoteScreensStale = true
    @Published var permissionRefreshToken = UUID()
    @Published var lockOnDisconnect = false

    let localPeerId = "mac"
    let remotePeerId = "windows"

    private let history = ClipboardHistory()
    private var kmSession: MacKmSession?
    private var receiverSession: MacReceiverSession?
    private var clipboardSession: ClipboardTextSession?
    private var controlSession: DevControlSession?
    private var keepAliveTimer: Timer?

    init() {
        refreshDisplays()
        loadLayoutState()
        reconcileLayout()
    }

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
            startControl(settings: settings)
            startKm(settings: settings)
        case .receiveFromWindows:
            startControl(settings: settings)
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

        keepAliveTimer?.invalidate()
        keepAliveTimer = nil
        controlSession?.close()
        controlSession = nil
        controlRunning = false

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
        requestInputMonitoring()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.openSystemSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
        }
    }

    func requestInputMonitoring() {
        let granted = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        appendLog(granted ? "Input Monitoring granted" : "Input Monitoring requested; enable BarelyReal in System Settings")
        refreshPermissions()
    }

    func resetBarelyRealPermissions() {
        runTccutilReset(service: "Accessibility")
        runTccutilReset(service: "ListenEvent")
        refreshPermissions()
        appendLog("Reset BarelyReal permissions. Enable Accessibility and Input Monitoring again.")
        openAccessibilitySettings()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.openInputMonitoringSettings()
        }
    }

    private func startReceiver(settings: ConnectionSettings) {
        receiverSession?.stop()
        let session = MacReceiverSession(
            kmPort: UInt16(settings.kmPort),
            allowedPeerHost: settings.peerHost
        ) { [weak self] message in
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
            appendLog("Receiver started on UDP :\(settings.kmPort), trusted peer \(settings.peerHost). Lock-on-disconnect: \(lockOnDisconnect ? "on" : "off")")
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
        refreshDisplays()
        reconcileLayout()

        do {
            let session = MacKmSession(
                peerHost: settings.peerHost,
                peerPort: UInt16(settings.kmPort),
                localPeerId: localPeerId,
                remotePeerId: remotePeerId,
                layoutProvider: { [weak self] in self?.virtualLayout ?? Layout(screens: []) },
                remoteDisplaysProvider: { [weak self] in self?.remoteDisplays ?? [] },
                scrollSpeed: settings.scrollSpeed
            ) { [weak self] message in
                Task { @MainActor in self?.appendLog(message) }
            }

            try session.start()
            kmSession = session
            kmRunning = true
            appendLog("KM started: \(settings.peerHost):\(settings.kmPort), layout screens \(virtualLayout.screens.count), scroll \(settings.scrollSpeed)/20")
        } catch {
            kmRunning = false
            lastError = "KM start failed: \(error)"
            appendLog(lastError ?? "KM start failed")
        }
    }

    private func startControl(settings: ConnectionSettings) {
        controlSession?.close()
        keepAliveTimer?.invalidate()

        let session = DevControlSession()
        session.onLog = { [weak self] message in
            Task { @MainActor in self?.appendLog(message) }
        }
        session.onScreenAnnounce = { [weak self] announcement in
            Task { @MainActor in self?.applyRemoteAnnouncement(announcement) }
        }
        session.onLayoutSync = { [weak self] message in
            Task { @MainActor in self?.applyRemoteLayout(message) }
        }

        do {
            try session.start(localPort: UInt16(settings.controlPort), peerHost: settings.peerHost, peerPort: UInt16(settings.controlPort))
            controlSession = session
            controlRunning = true
            sendControlSnapshot()
            keepAliveTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak session] _ in
                session?.sendKeepAlive()
            }
        } catch {
            controlRunning = false
            lastError = "Control start failed: \(error)"
            appendLog(lastError ?? "Control start failed")
        }
    }

    func refreshDisplays() {
        localDisplays = DisplayEnumerator.localDisplays(peerId: localPeerId)
    }

    func moveRemoteGroup(dx: Int, dy: Int, snap: Bool) {
        guard virtualLayout.bounds(peerId: remotePeerId) != nil else { return }
        var next = virtualLayout.translated(peerId: remotePeerId, dx: dx, dy: dy)
        if snap {
            next = snappedRemoteLayout(next)
        }
        virtualLayout = next
        saveLayoutState()
        controlSession?.sendLayoutSync(.init(layout: virtualLayout.screens))
        appendLog("Layout updated: \(remotePeerId) moved")
    }

    private func sendControlSnapshot() {
        refreshDisplays()
        let screens = localDisplays.map(AnnouncedScreen.init(display:))
        controlSession?.sendHello(.init(name: Host.current().localizedName ?? "Mac", os: "macOS", ver: "0.1.0", screens: screens))
        controlSession?.sendScreenAnnounce(.init(peerId: localPeerId, screens: screens))
        controlSession?.sendLayoutSync(.init(layout: virtualLayout.screens))
    }

    private func applyRemoteAnnouncement(_ announcement: ScreenAnnouncement) {
        guard announcement.peerId != localPeerId else { return }
        remoteDisplays = announcement.screens.map { $0.displayInfo(peerId: remotePeerId) }
        remoteScreensStale = false
        reconcileLayout()
        saveLayoutState()
        appendLog("Peer screens updated: \(remoteDisplays.count)")
    }

    private func applyRemoteLayout(_ message: LayoutSyncMessage) {
        refreshDisplays()
        let incoming = Layout(screens: message.layout)
        let localNative = localDisplays.map(\.screenRect)
        guard let incomingLocal = incoming.bounds(peerId: localPeerId),
              let nativeLocal = Layout(screens: localNative).bounds(peerId: localPeerId)
        else {
            virtualLayout = snappedRemoteLayout(Layout(screens: localNative + incoming.screens(peerId: remotePeerId)))
            saveLayoutState()
            return
        }

        let dx = nativeLocal.minX - incomingLocal.minX
        let dy = nativeLocal.minY - incomingLocal.minY
        let translatedRemote = incoming.screens(peerId: remotePeerId).map {
            ScreenRect(peerId: $0.peerId, screenId: $0.screenId, x: $0.x + dx, y: $0.y + dy, width: $0.width, height: $0.height)
        }
        virtualLayout = snappedRemoteLayout(Layout(screens: localNative + translatedRemote))
        saveLayoutState()
        appendLog("Layout synced from peer")
    }

    private func reconcileLayout() {
        refreshDisplays()
        let localScreens = localDisplays.map(\.screenRect)
        let remoteScreens = remoteDisplays.map(\.screenRect)
        guard !localScreens.isEmpty else {
            virtualLayout = Layout(screens: remoteScreens)
            return
        }
        guard !remoteScreens.isEmpty else {
            virtualLayout = Layout(screens: localScreens + virtualLayout.screens(peerId: remotePeerId))
            return
        }

        let existingRemote = virtualLayout.screens(peerId: remotePeerId)
        let remoteIds = Set(remoteScreens.map(\.screenId))
        if !existingRemote.isEmpty, Set(existingRemote.map(\.screenId)) == remoteIds {
            let existingById = Dictionary(uniqueKeysWithValues: existingRemote.map { ($0.screenId, $0) })
            let updatedRemote = remoteScreens.map { native in
                if let existing = existingById[native.screenId] {
                    return ScreenRect(peerId: remotePeerId, screenId: native.screenId, x: existing.x, y: existing.y, width: native.width, height: native.height)
                }
                return native
            }
            virtualLayout = snappedRemoteLayout(Layout(screens: localScreens + updatedRemote))
            return
        }

        let localBounds = Layout(screens: localScreens).bounds(peerId: localPeerId)
        let remoteBounds = Layout(screens: remoteScreens).bounds(peerId: remotePeerId)
        guard let localBounds, let remoteBounds else {
            virtualLayout = snappedRemoteLayout(Layout(screens: localScreens + remoteScreens))
            return
        }

        let dx = localBounds.minX - remoteBounds.maxX
        let dy = localBounds.minY - remoteBounds.minY
        let translatedRemote = remoteScreens.map {
            ScreenRect(peerId: remotePeerId, screenId: $0.screenId, x: $0.x + dx, y: $0.y + dy, width: $0.width, height: $0.height)
        }
        virtualLayout = snappedRemoteLayout(Layout(screens: localScreens + translatedRemote))
    }

    private func snappedRemoteLayout(_ layout: Layout) -> Layout {
        layout.stickySnapped(peerId: remotePeerId, toPeerId: localPeerId)
    }

    private func saveLayoutState() {
        guard let data = try? JSONEncoder().encode(virtualLayout),
              let remoteData = try? JSONEncoder().encode(remoteDisplays)
        else { return }
        UserDefaults.standard.set(data, forKey: "layout.virtual")
        UserDefaults.standard.set(remoteData, forKey: "layout.remoteDisplays")
    }

    private func loadLayoutState() {
        if let data = UserDefaults.standard.data(forKey: "layout.virtual"),
           let layout = try? JSONDecoder().decode(Layout.self, from: data) {
            virtualLayout = layout
        }
        if let data = UserDefaults.standard.data(forKey: "layout.remoteDisplays"),
           let displays = try? JSONDecoder().decode([DisplayInfo].self, from: data) {
            remoteDisplays = displays
            remoteScreensStale = !displays.isEmpty
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

    func exportDiagnostics() {
        do {
            let url = try DiagnosticsBundle.write(.init(
                kmRunning: kmRunning,
                clipboardRunning: clipboardRunning,
                controlRunning: controlRunning,
                receiverLinkUp: receiverLinkUp,
                lockOnDisconnect: lockOnDisconnect,
                localDisplays: localDisplays,
                remoteDisplays: remoteDisplays,
                remoteScreensStale: remoteScreensStale,
                virtualLayout: virtualLayout,
                logLines: logLines,
                lastError: lastError
            ))
            appendLog("Diagnostics exported: \(url.path)")
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            lastError = "Diagnostics export failed: \(error)"
            appendLog(lastError ?? "Diagnostics export failed")
        }
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
    var controlPort: Int
    var kmPort: Int
    var clipboardPort: Int
    var scrollSpeed: Int
    var mode: MacKmMode = .sendToWindows
}
