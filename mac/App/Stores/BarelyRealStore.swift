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
    @Published private(set) var discoveredPeers: [MdnsPeer] = []
    @Published private(set) var suggestedPeerHost = ""
    @Published private(set) var localFingerprint = "unavailable"
    @Published private(set) var pinnedPeers: [PairingService.PinnedPeer] = []
    @Published var permissionRefreshToken = UUID()
    @Published var lockOnDisconnect = false
    var onSuggestedPeerHost: ((String) -> Void)?

    let localPeerId = "mac"
    let remotePeerId = "windows"

    private let history = ClipboardHistory()
    private var kmSession: MacKmSession?
    private var receiverSession: MacReceiverSession?
    private var clipboardSession: ClipboardTextSession?
    private var controlSession: DevControlSession?
    private var keepAliveTimer: Timer?
    private let mdnsAdvertiser = MdnsAdvertiser()
    private let mdnsBrowser = MdnsBrowser()
    private let lanPeerScanner = LanPeerScanner()
    private let deviceIdentity = DeviceIdentity()
    private let pairingService = PairingService()
    private var discoveryStarted = false
    private var lastSuggestedPeerHost: String?
    private var currentControlPort = 24_800
    private var mdnsRemotePeers: [MdnsPeer] = []
    private var lanScanHosts: [String] = []
    private var lanScanTimer: Timer?
    private var lanScanInFlight = false

    init() {
        loadIdentityAndTrust()
        refreshDisplays()
        loadLayoutState()
        reconcileLayout()
        startDiscovery(controlPort: 24_800)
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

        notePeerTrustState(settings: settings)

        if !accessibilityGranted {
            appendLog("Accessibility permission is missing; KM capture may not start.")
        }
        if !inputMonitoringGranted {
            appendLog("Input Monitoring is not granted; continuing with Accessibility event capture.")
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
        notePeerTrustState(settings: settings)
        if clipboardSession == nil {
            startClipboard(settings: settings)
        }

        clipboardSession?.sendTestText()
        appendLog("Clipboard text test sent")
    }

    func sendClipboardImageTest(settings: ConnectionSettings) {
        notePeerTrustState(settings: settings)
        if clipboardSession == nil {
            startClipboard(settings: settings)
        }

        clipboardSession?.sendTestImage()
        appendLog("Clipboard image test sent")
    }

    func sendClipboardFileTest(settings: ConnectionSettings) {
        notePeerTrustState(settings: settings)
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
        appendLog(granted ? "Input Monitoring granted" : "Input Monitoring requested. If macOS does not list BarelyReal, Start can still use Accessibility capture in this dev build.")
        refreshPermissions()
    }

    func resetBarelyRealPermissions() {
        stop()
        resetTccService("Accessibility")
        resetTccService("ListenEvent")
        refreshPermissions()
        appendLog("Reset BarelyReal permissions. Restarting and opening Accessibility.")
        restartAppAndOpenAccessibility()
    }

    private func startReceiver(settings: ConnectionSettings) {
        receiverSession?.stop()
        let session = MacReceiverSession(
            kmPort: UInt16(settings.kmPort),
            allowedPeerHost: settings.peerHost,
            kmSharedSecret: settings.kmSharedSecret
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
                scrollSpeed: settings.scrollSpeed,
                kmSharedSecret: settings.kmSharedSecret
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
        startDiscovery(controlPort: settings.controlPort)

        let session = configuredControlSession()

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

    private func configuredControlSession() -> DevControlSession {
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
        return session
    }

    private func startDiscovery(controlPort: Int) {
        currentControlPort = controlPort
        let deviceName = Host.current().localizedName ?? "Mac"
        mdnsAdvertiser.start(
            deviceName: deviceName,
            port: UInt16(clamping: controlPort),
            os: "macOS",
            version: "0.1.0",
            peerId: localPeerId,
            publicKeyFingerprint: localFingerprint,
            onLog: { [weak self] message in
                Task { @MainActor in self?.appendLog(message) }
            }
        )

        if !discoveryStarted {
            discoveryStarted = true
            mdnsBrowser.onLog = { [weak self] message in
                Task { @MainActor in self?.appendLog(message) }
            }
            mdnsBrowser.onChange = { [weak self] peers in
                Task { @MainActor in self?.applyDiscoveredPeers(peers) }
            }
            mdnsBrowser.start()
        }

        if lanScanTimer == nil {
            lanScanTimer = Timer.scheduledTimer(withTimeInterval: 18, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.runLanPeerScan() }
            }
        }
        runLanPeerScan()
    }

    func refreshDisplays() {
        localDisplays = DisplayEnumerator.localDisplays(peerId: localPeerId)
    }

    func isTrusted(peer: MdnsPeer) -> Bool {
        trustState(peer: peer) == .trusted
    }

    func trustState(peer: MdnsPeer) -> PairingService.PeerTrustState {
        pairingService.trustState(publicKeyFingerprint: peer.publicKeyFingerprint, displayName: peer.name)
    }

    func devPairingPin(for peer: MdnsPeer) -> String? {
        guard isUsableFingerprint(peer.publicKeyFingerprint),
              isUsableFingerprint(localFingerprint)
        else { return nil }
        return PairingService.devPairingPin(
            localFingerprint: localFingerprint,
            peerFingerprint: peer.publicKeyFingerprint
        )
    }

    func trust(peer: MdnsPeer) {
        guard isUsableFingerprint(peer.publicKeyFingerprint) else {
            appendLog("Cannot trust peer without an advertised fingerprint")
            return
        }
        let pinned = PairingService.PinnedPeer(
            publicKeyFingerprint: peer.publicKeyFingerprint,
            displayName: peer.name
        )
        pairingService.pinPeer(pinned)
        pinnedPeers = pairingService.loadPinnedPeers()
        appendLog("Trusted dev peer \(peer.name) (\(shortFingerprint(peer.publicKeyFingerprint)))")
        if let host = peer.bestHost {
            lastSuggestedPeerHost = host
            onSuggestedPeerHost?(host)
        }
    }

    func untrust(peer: MdnsPeer) {
        let removedFingerprint: String
        switch trustState(peer: peer) {
        case .trusted:
            guard isUsableFingerprint(peer.publicKeyFingerprint) else { return }
            removedFingerprint = peer.publicKeyFingerprint
        case .keyChanged(let expectedFingerprint):
            removedFingerprint = expectedFingerprint
        case .unknownKey, .unpaired:
            return
        }
        pairingService.unpinPeer(fingerprint: removedFingerprint)
        pinnedPeers = pairingService.loadPinnedPeers()
        appendLog("Forgot dev peer \(peer.name) (\(shortFingerprint(removedFingerprint)))")
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

    private func applyDiscoveredPeers(_ peers: [MdnsPeer]) {
        mdnsRemotePeers = peers.filter { peer in
            peer.peerId != localPeerId
                && (peer.peerId == remotePeerId || peer.os.localizedCaseInsensitiveContains("win"))
        }
        rebuildDiscoveredPeers()
    }

    private func runLanPeerScan() {
        guard !lanScanInFlight else { return }
        lanScanInFlight = true
        let port = UInt16(clamping: currentControlPort)
        lanPeerScanner.scan(controlPort: port) { [weak self] hosts in
            Task { @MainActor in
                guard let self else { return }
                self.lanScanInFlight = false
                if hosts != self.lanScanHosts {
                    self.lanScanHosts = hosts
                    if !hosts.isEmpty {
                        self.appendLog("LAN scan found BarelyReal control on \(hosts.joined(separator: ", "))")
                    }
                    self.rebuildDiscoveredPeers()
                }
            }
        }
    }

    private func rebuildDiscoveredPeers() {
        var merged = mdnsRemotePeers
        let knownHosts = Set(
            merged.flatMap { peer in
                ([peer.bestHost, peer.hostName] + peer.addresses.map(Optional.some))
                    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            }
        )

        let scannedPeers = lanScanHosts.compactMap { host -> MdnsPeer? in
            let normalized = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !knownHosts.contains(normalized) else { return nil }
            return MdnsPeer(
                name: "BarelyReal peer",
                os: "Windows",
                version: "LAN scan",
                publicKeyFingerprint: "",
                peerId: remotePeerId,
                hostName: nil,
                addresses: [host],
                port: currentControlPort,
                stale: false
            )
        }

        merged.append(contentsOf: scannedPeers)
        discoveredPeers = merged.sorted { lhs, rhs in
            if lhs.stale != rhs.stale { return !lhs.stale }
            let leftRank = peerAutoConnectRank(lhs)
            let rightRank = peerAutoConnectRank(rhs)
            if leftRank != rightRank { return leftRank < rightRank }
            return (lhs.bestHost ?? lhs.name).localizedStandardCompare(rhs.bestHost ?? rhs.name) == .orderedAscending
        }

        guard let peer = discoveredPeers.first(where: { !$0.stale }),
              let host = autoConnectHost(for: peer)
        else { return }
        suggestPeerHost(host, source: peer.version == "LAN scan" ? "LAN scan" : "mDNS")
    }

    private func peerAutoConnectRank(_ peer: MdnsPeer) -> Int {
        guard !peer.stale else { return 100 }
        if peer.version == "LAN scan" { return 0 }
        guard let host = autoConnectHost(for: peer) else { return 90 }
        return hostPriority(host)
    }

    private func autoConnectHost(for peer: MdnsPeer) -> String? {
        let candidates = peerHostCandidates(peer)

        if peer.version == "LAN scan" {
            return candidates.first
        }

        if let sameSubnet = candidates.first(where: isOnPreferredLocalSubnet) {
            return sameSubnet
        }

        // Do not auto-select 10.x from mDNS. VPN adapters such as NordLynx commonly
        // advertise only 10.x, which looks private but is a bad handoff target.
        return candidates.first { hostPriority($0) <= 2 }
    }

    private func peerHostCandidates(_ peer: MdnsPeer) -> [String] {
        var seen = Set<String>()
        let raw = peer.addresses + [peer.bestHost, peer.hostName].compactMap { $0 }
        return raw.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  !trimmed.contains(":"),
                  seen.insert(trimmed.lowercased()).inserted
            else { return nil }
            return trimmed
        }
        .sorted { hostPriority($0) < hostPriority($1) }
    }

    private func isOnPreferredLocalSubnet(_ host: String) -> Bool {
        LanPeerScanner.preferredLocalPrefixes().contains { host.hasPrefix($0) }
    }

    private func hostPriority(_ host: String) -> Int {
        let parts = host.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return 100 }
        if parts[0] == 192 && parts[1] == 168 { return 0 }
        if parts[0] == 172 && (16...31).contains(parts[1]) { return 1 }
        if parts[0] == 169 && parts[1] == 254 { return 2 }
        if parts[0] == 10 { return 8 }
        return 20
    }

    private func suggestPeerHost(_ host: String, source: String) {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != lastSuggestedPeerHost else { return }

        lastSuggestedPeerHost = trimmed
        suggestedPeerHost = trimmed
        appendLog("Auto-detected Windows peer via \(source): \(trimmed)")
        onSuggestedPeerHost?(trimmed)
        startPassiveControlIfNeeded(peerHost: trimmed)
    }

    private func startPassiveControlIfNeeded(peerHost: String) {
        guard !kmRunning, !clipboardRunning else { return }

        controlSession?.close()
        keepAliveTimer?.invalidate()

        let session = configuredControlSession()
        do {
            try session.start(
                localPort: UInt16(clamping: currentControlPort),
                peerHost: peerHost,
                peerPort: UInt16(clamping: currentControlPort)
            )
            controlSession = session
            controlRunning = true
            sendControlSnapshot()
            keepAliveTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak session] _ in
                session?.sendKeepAlive()
            }
            appendLog("Passive control ready for auto-detected peer \(peerHost):\(currentControlPort)")
        } catch {
            controlRunning = false
            appendLog("Passive control start failed: \(error)")
        }
    }

    private func notePeerTrustState(settings: ConnectionSettings) {
        let peerHost = settings.peerHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !peerHost.isEmpty else { return }

        guard let peer = discoveredPeer(matchingHost: peerHost) else {
            appendLog("Trust disabled: no discovered fingerprint for \(peerHost); starting dev connection.")
            return
        }

        switch trustState(peer: peer) {
        case .trusted:
            appendLog("Trust disabled: \(peer.name) is trusted; starting dev connection.")
        case .unknownKey:
            appendLog("Trust disabled: \(peer.name) has no advertised fingerprint; starting dev connection.")
        case .unpaired:
            appendLog("Trust disabled: \(peer.name) is unpaired; starting dev connection anyway.")
        case .keyChanged(let expectedFingerprint):
            appendLog("Trust disabled: \(peer.name) key changed (expected \(shortFingerprint(expectedFingerprint)), saw \(shortFingerprint(peer.publicKeyFingerprint))); starting dev connection anyway.")
        }
    }

    private func discoveredPeer(matchingHost host: String) -> MdnsPeer? {
        let normalized = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }

        return discoveredPeers.first { peer in
            guard !peer.stale else { return false }
            let candidates = ([peer.bestHost, peer.hostName] + peer.addresses.map(Optional.some))
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            return candidates.contains(normalized)
        }
    }

    private func loadIdentityAndTrust() {
        do {
            let identity = try deviceIdentity.loadOrGenerate()
            localFingerprint = identity.publicKeyFingerprint
        } catch {
            localFingerprint = "unavailable"
            appendLog("Device identity unavailable: \(error)")
        }
        pinnedPeers = pairingService.loadPinnedPeers()
    }

    private func isUsableFingerprint(_ fingerprint: String) -> Bool {
        let trimmed = fingerprint.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != "dev" && trimmed != "unavailable"
    }

    private func shortFingerprint(_ fingerprint: String) -> String {
        let trimmed = fingerprint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 12 else { return trimmed.isEmpty ? "none" : trimmed }
        return "\(trimmed.prefix(6))...\(trimmed.suffix(6))"
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

    private func resetTccService(_ service: String) {
        runTccutilReset(service: service, bundleIdentifier: "local.barelyreal.mac")
        runTccutilReset(service: service, bundleIdentifier: "com.barelyreal.mac")
    }

    private func runTccutilReset(service: String, bundleIdentifier: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", service, bundleIdentifier]
        try? process.run()
        process.waitUntilExit()
    }

    private func restartAppAndOpenAccessibility() {
        let bundleURL = Bundle.main.bundleURL
        let installedURL = URL(fileURLWithPath: "/Applications/BarelyReal.app")
        let appURL = bundleURL.pathExtension == "app" ? bundleURL : installedURL
        let accessibilityURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        let script = """
        sleep 0.45
        if [ -d \(Self.shellQuote(appURL.path)) ]; then
          open -n \(Self.shellQuote(appURL.path))
        elif [ -d \(Self.shellQuote(installedURL.path)) ]; then
          open -n \(Self.shellQuote(installedURL.path))
        fi
        sleep 0.35
        open \(Self.shellQuote(accessibilityURL))
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", script]
        try? process.run()
        NSApp.terminate(nil)
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
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
    var kmSharedSecret: String
    var mode: MacKmMode = .sendToWindows
}
