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
        case .home: "Home"
        case .devices: "Devices"
        case .clipboard: "Clipboard"
        case .activity: "Activity"
        case .settings: "Settings"
        }
    }

    var icon: String {
        switch self {
        case .home: "house.fill"
        case .devices: "macbook.and.iphone"
        case .clipboard: "doc.on.clipboard"
        case .activity: "waveform"
        case .settings: "gearshape.fill"
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
            List(AppSection.allCases, selection: $selection) { section in
                NavigationLink(value: section) {
                    Label(section.title, systemImage: section.icon)
                }
            }
            .listStyle(.sidebar)
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
                        .foregroundStyle(.tint)
                    Text("BarelyReal")
                        .font(.headline)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                statusToolbarBadge
            }
        }
        .onAppear {
            // Sync persisted toggle into the receiver session.
            store.setLockOnDisconnect(lockOnDisconnect)
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

    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            HStack(spacing: 8) {
                Circle()
                    .fill(store.kmRunning ? Color.green : Color.secondary.opacity(0.4))
                    .frame(width: 8, height: 8)
                Text(store.kmRunning ? "Running" : "Stopped")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    private var statusToolbarBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(store.kmRunning ? Color.green : Color.secondary.opacity(0.5))
                .frame(width: 8, height: 8)
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
