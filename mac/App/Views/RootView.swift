import SwiftUI

enum AppSection: Hashable, CaseIterable, Identifiable {
    case home
    case devices
    case clipboard
    case activity
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .home: "Control"
        case .devices: "Layout"
        case .clipboard: "Clipboard"
        case .activity: "Telemetry"
        case .settings: "Systems"
        }
    }

    var icon: String {
        switch self {
        case .home: "command.circle.fill"
        case .devices: "macbook.and.iphone"
        case .clipboard: "doc.on.clipboard"
        case .activity: "waveform"
        case .settings: "gearshape.fill"
        }
    }

    var detail: String {
        switch self {
        case .home: "handoff"
        case .devices: "monitors"
        case .clipboard: "shared"
        case .activity: "logs"
        case .settings: "ports"
        }
    }
}

struct RootView: View {
    @ObservedObject var store: BarelyRealStore

    @AppStorage("connection.peerHost") private var peerHost = "192.168.0.102"
    @AppStorage("connection.controlPort") private var controlPort = 24_800
    @AppStorage("connection.kmPort") private var kmPort = 24_801
    @AppStorage("connection.clipboardPort") private var clipboardPort = 24_802
    @AppStorage("connection.scrollSpeed") private var scrollSpeed = 7
    @AppStorage("connection.mode") private var modeRaw = MacKmMode.sendToWindows.rawValue
    @AppStorage("connection.lockOnDisconnect") private var lockOnDisconnect = false
    @State private var kmSharedSecret = ""
    @AppStorage("connection.peerMac") private var peerMac = ""
    @AppStorage("connection.peerBroadcast") private var peerBroadcast = "192.168.0.255"

    @State private var selection: AppSection = .home

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                sidebarHeader
                List(AppSection.allCases, selection: $selection) { section in
                    NavigationLink(value: section) {
                        HStack(spacing: 10) {
                            Image(systemName: section.icon)
                                .foregroundStyle(.secondary)
                                .frame(width: 17)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(section.title)
                                    .lineLimit(1)
                                Text(section.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listStyle(.sidebar)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
            .toolbar(removing: .sidebarToggle)
            .safeAreaInset(edge: .bottom) {
                sidebarFooter
            }
        } detail: {
            detailView
                .navigationSplitViewColumnWidth(min: 560, ideal: 760)
        }
        .navigationTitle("BarelyReal")
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.connected.to.line.below")
                        .foregroundStyle(VisionPalette.blue)
                    Text("Codex Vision")
                        .font(.headline)
                    Text("BarelyReal")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                statusToolbarBadge
            }
        }
        .onAppear {
            // Sync persisted toggle into the receiver session.
            store.setLockOnDisconnect(lockOnDisconnect)
            store.onSuggestedPeerHost = { host in
                let current = peerHost.trimmingCharacters(in: .whitespacesAndNewlines)
                if current.isEmpty || current == "192.168.0.102" {
                    peerHost = host
                }
            }
        }
        .onDisappear {
            store.onSuggestedPeerHost = nil
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .home:
            HomeView(
                store: store,
                peerHost: $peerHost,
                modeRaw: $modeRaw,
                kmPort: kmPort,
                clipboardPort: clipboardPort,
                onStart: start,
                onStop: store.stop,
                onTestText: { store.sendClipboardTest(settings: currentSettings) },
                onTestImage: { store.sendClipboardImageTest(settings: currentSettings) }
            )
        case .devices:
            DevicesView(
                store: store,
                peerHost: $peerHost,
                peerMac: $peerMac,
                peerBroadcast: $peerBroadcast
            )
        case .clipboard:
            ClipboardHistoryView(store: store)
        case .activity:
            ActivityView(store: store)
        case .settings:
            SettingsView(
                store: store,
                controlPort: $controlPort,
                kmPort: $kmPort,
                clipboardPort: $clipboardPort,
                scrollSpeed: $scrollSpeed,
                lockOnDisconnect: $lockOnDisconnect,
                kmSharedSecret: $kmSharedSecret
            )
        }
    }

    // MARK: - Sidebar accessories

    private var sidebarHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                VisionGlyphBadge(systemImage: "cursorarrow.motionlines", tint: VisionPalette.blue, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Codex Vision")
                        .font(.headline)
                    Text("shared desktop")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 6)
        }
    }

    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    VisionStatusDot(kind: store.kmRunning ? .active : .idle)
                    Text(store.kmRunning ? "Session active" : "Ready")
                        .font(.caption.weight(.medium))
                    Spacer()
                }
                HStack(spacing: 8) {
                    Image(systemName: store.clipboardRunning ? "doc.on.clipboard.fill" : "doc.on.clipboard")
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                    Text(store.clipboardRunning ? "Clipboard linked" : "Clipboard idle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private var statusToolbarBadge: some View {
        HStack(spacing: 6) {
            VisionStatusDot(kind: store.kmRunning ? .active : .idle)
            Text(store.kmRunning ? "Connected" : "Idle")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.quaternary, in: Capsule())
    }

    // MARK: - Helpers

    private var currentSettings: ConnectionSettings {
        ConnectionSettings(
            peerHost: peerHost.trimmingCharacters(in: .whitespacesAndNewlines),
            controlPort: controlPort,
            kmPort: kmPort,
            clipboardPort: clipboardPort,
            scrollSpeed: min(max(scrollSpeed, 1), 20),
            kmSharedSecret: kmSharedSecret.trimmingCharacters(in: .whitespacesAndNewlines),
            mode: MacKmMode(rawValue: modeRaw) ?? .sendToWindows
        )
    }

    private func start() {
        store.start(settings: currentSettings)
    }
}
