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
        case .home: "Handoff"
        case .devices: "Displays"
        case .clipboard: "Clipboard"
        case .activity: "Telemetry"
        case .settings: "System"
        }
    }

    var icon: String {
        switch self {
        case .home: "bolt"
        case .devices: "desktopcomputer"
        case .clipboard: "clipboard"
        case .activity: "waveform.path.ecg"
        case .settings: "gearshape"
        }
    }

    var detail: String {
        switch self {
        case .home: "Control devices"
        case .devices: "Manage screens"
        case .clipboard: "Shared history"
        case .activity: "System logs"
        case .settings: "Ports & settings"
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
        HStack(spacing: 0) {
            sidebar
                .frame(width: 232)
                .background(ProductPalette.sidebar)

            Rectangle()
                .fill(ProductPalette.hairline)
                .frame(width: 1)

            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(ProductPalette.background)
        }
        .frame(minWidth: 1120, minHeight: 760)
        .background(ProductPalette.background)
        .onAppear {
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

    private var sidebar: some View {
        VStack(spacing: 0) {
            brandBlock
                .padding(.top, 54)
                .padding(.bottom, 34)

            VStack(spacing: 8) {
                ForEach(AppSection.allCases) { section in
                    SidebarButton(
                        section: section,
                        isSelected: selection == section,
                        action: { selection = section }
                    )
                }
            }
            .padding(.horizontal, 10)

            Spacer(minLength: 24)

            SidebarSessionCard(store: store)
                .padding(.horizontal, 12)
                .padding(.bottom, 20)

            HStack(spacing: 10) {
                BottomIconButton(systemImage: "gearshape") {
                    selection = .settings
                }
                BottomIconButton(systemImage: "questionmark.circle") {
                    selection = .activity
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 18)
        }
    }

    private var brandBlock: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(
                        colors: [ProductPalette.blue, ProductPalette.violet],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 56, height: 56)
                    .shadow(color: ProductPalette.blue.opacity(0.35), radius: 18, y: 8)
                Image(systemName: "display.2")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
            }

            VStack(spacing: 4) {
                Text("BarelyReal")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(ProductPalette.text)
                HStack(spacing: 7) {
                    Circle()
                        .fill(store.kmRunning || store.clipboardRunning ? ProductPalette.green : ProductPalette.muted)
                        .frame(width: 8, height: 8)
                    Text(store.kmRunning || store.clipboardRunning ? "Connected" : "Ready")
                        .font(.callout)
                        .foregroundStyle(ProductPalette.subtext)
                }
            }
        }
    }

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

private struct SidebarButton: View {
    let section: AppSection
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 15) {
                Image(systemName: section.icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(isSelected ? .white : ProductPalette.subtext)
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 2) {
                    Text(section.title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(ProductPalette.text)
                    Text(section.detail)
                        .font(.caption)
                        .foregroundStyle(ProductPalette.subtext)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? ProductPalette.selectedRow : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? ProductPalette.border : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct SidebarSessionCard: View {
    @ObservedObject var store: BarelyRealStore

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 10) {
                Image(systemName: store.kmRunning ? "checkmark.circle" : "circle")
                    .foregroundStyle(store.kmRunning ? ProductPalette.green : ProductPalette.muted)
                Text(store.kmRunning ? "Session active" : "Session idle")
                    .font(.caption.weight(.medium))
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(ProductPalette.muted)
            }
            HStack(spacing: 10) {
                Image(systemName: "link")
                    .foregroundStyle(ProductPalette.muted)
                Text(store.clipboardRunning ? "Clipboard linked" : "Clipboard idle")
                    .font(.caption)
                    .foregroundStyle(ProductPalette.subtext)
            }
        }
        .foregroundStyle(ProductPalette.text)
        .padding(16)
        .background(ProductPalette.card.opacity(0.88), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(ProductPalette.border, lineWidth: 1)
        )
    }
}

private struct BottomIconButton: View {
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(ProductPalette.subtext)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(ProductPalette.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(ProductPalette.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

enum ProductPalette {
    static let background = Color(red: 0.045, green: 0.065, blue: 0.095)
    static let sidebar = Color(red: 0.055, green: 0.075, blue: 0.110)
    static let card = Color(red: 0.075, green: 0.100, blue: 0.145)
    static let cardElevated = Color(red: 0.095, green: 0.125, blue: 0.175)
    static let selectedRow = Color.white.opacity(0.085)
    static let border = Color.white.opacity(0.125)
    static let hairline = Color.white.opacity(0.10)
    static let text = Color(red: 0.93, green: 0.96, blue: 1.0)
    static let subtext = Color(red: 0.66, green: 0.71, blue: 0.78)
    static let muted = Color(red: 0.45, green: 0.50, blue: 0.58)
    static let blue = Color(red: 0.15, green: 0.37, blue: 0.95)
    static let violet = Color(red: 0.33, green: 0.20, blue: 0.82)
    static let green = Color(red: 0.25, green: 0.90, blue: 0.43)
    static let amber = Color(red: 0.96, green: 0.66, blue: 0.20)
    static let red = Color(red: 0.92, green: 0.18, blue: 0.22)
}
