import BarelyRealCore
import SwiftUI

struct DevicesView: View {
    @ObservedObject var store: BarelyRealStore

    @Binding var peerHost: String
    @Binding var peerMac: String
    @Binding var peerBroadcast: String

    var body: some View {
        VisionPage(
            title: "Layout Matrix",
            subtitle: "Every screen in one shared coordinate plane.",
            systemImage: "rectangle.split.2x1"
        ) {
            deviceCard
            pairingCard
            wakeOnLanCard
            pendingFeaturesNote
        }
    }

    private var wakeOnLanCard: some View {
        VisionCard {
            HStack(spacing: 8) {
                Image(systemName: "powerplug.fill")
                    .foregroundStyle(VisionPalette.amber)
                Text("Wake on LAN")
                    .font(.callout.weight(.semibold))
                Spacer()
            }

            Text("Send a magic packet to wake a sleeping Windows machine. Requires WoL enabled in BIOS and Windows power options.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .center, spacing: 12) {
                Text("MAC")
                    .frame(width: 110, alignment: .leading)
                    .font(.callout)
                TextField("AA:BB:CC:DD:EE:FF", text: $peerMac)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.callout, design: .monospaced))
            }

            HStack(alignment: .center, spacing: 12) {
                Text("Broadcast")
                    .frame(width: 110, alignment: .leading)
                    .font(.callout)
                TextField("192.168.0.255", text: $peerBroadcast)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.callout, design: .monospaced))
                Button {
                    store.wakePeer(macAddress: peerMac, broadcastHost: peerBroadcast)
                } label: {
                    Label("Wake", systemImage: "bolt.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(peerMac.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private var deviceCard: some View {
        VisionCard {
            HStack(alignment: .top, spacing: 16) {
                VisionGlyphBadge(systemImage: "pc", tint: VisionPalette.blue, size: 48)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Windows machine")
                            .font(.headline)
                        Text("Default peer")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                    Text(peerHost.isEmpty ? "No address set" : peerHost)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                    Text(store.remoteScreensStale ? "Last known screens" : "\(store.remoteDisplays.count) screen\(store.remoteDisplays.count == 1 ? "" : "s") synced")
                        .font(.caption)
                        .foregroundStyle(store.remoteScreensStale ? VisionPalette.amber : .secondary)
                }

                Spacer()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Layout")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 16)
                LayoutCanvas(
                    layout: store.virtualLayout,
                    localPeerId: store.localPeerId,
                    remotePeerId: store.remotePeerId,
                    remoteIsStale: store.remoteScreensStale,
                    onMoveRemote: { dx, dy, snap in
                        store.moveRemoteGroup(dx: dx, dy: dy, snap: snap)
                    }
                )
                Text("Drag the Windows monitor group to any side or corner of your Mac monitors.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            VisionDivider()
                .padding(.vertical, 2)

            VStack(spacing: 12) {
                editableRow(
                    title: "IP address",
                    placeholder: "192.168.0.102",
                    value: $peerHost
                )

                if !store.discoveredPeers.isEmpty {
                    discoveredPeersList
                }

                HStack(alignment: .center, spacing: 12) {
                    Text("Screens")
                        .frame(width: 110, alignment: .leading)
                        .font(.callout)
                    Text("\(store.localDisplays.count) Mac, \(store.remoteDisplays.count) Windows")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        store.refreshDisplays()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
            }
        }
    }

    private var pairingCard: some View {
        VisionCard {
            HStack(spacing: 8) {
                Image(systemName: "key.horizontal.fill")
                    .foregroundStyle(VisionPalette.blue)
                Text("Pairing & trust")
                    .font(.callout.weight(.semibold))
                Spacer()
                if let peer = selectedPeer {
                    trustBadge(for: peer)
                }
            }

            Text("Dev pairing scaffold. This pins the discovered peer fingerprint now; production pairing will bind this trust to the TLS PIN handshake.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            fingerprintRow(title: "This Mac", value: store.localFingerprint)

            if let peer = selectedPeer {
                fingerprintRow(
                    title: "Windows",
                    value: peer.publicKeyFingerprint.isEmpty ? "not advertised" : peer.publicKeyFingerprint
                )

                if let pin = store.devPairingPin(for: peer) {
                    HStack(alignment: .center, spacing: 12) {
                        Text("Dev PIN")
                            .frame(width: 110, alignment: .leading)
                            .font(.callout)
                        Text(pin)
                            .font(.system(.title3, design: .monospaced).weight(.semibold))
                            .textSelection(.enabled)
                        Text("Compare on Windows")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }

                HStack(spacing: 10) {
                    let trustState = store.trustState(peer: peer)
                    Button {
                        store.trust(peer: peer)
                    } label: {
                        Label("Trust peer", systemImage: "checkmark.shield.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.isTrusted(peer: peer) || store.devPairingPin(for: peer) == nil)

                    Button {
                        store.untrust(peer: peer)
                    } label: {
                        Label("Forget", systemImage: "trash")
                    }
                    .disabled(!(trustState == .trusted || isKeyChanged(trustState)))

                    Spacer()
                }
            } else {
                Label("No Windows fingerprint discovered yet. Start the Windows app or use manual IP for transport while discovery catches up.",
                      systemImage: "network.slash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var discoveredPeersList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Discovered on LAN")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(store.discoveredPeers) { peer in
                HStack(spacing: 10) {
                    Image(systemName: peer.stale ? "wifi.exclamationmark" : "network")
                            .foregroundStyle(peer.stale ? VisionPalette.amber : VisionPalette.mint)
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(peer.name)
                            .font(.callout.weight(.medium))
                        Text(discoveredPeerSubtitle(peer))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button("Use") {
                        if let host = peer.bestHost {
                            peerHost = host
                        }
                    }
                    .controlSize(.small)
                    .disabled(peer.bestHost == nil)
                }
                .padding(10)
                .background(Color(nsColor: .separatorColor).opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private func discoveredPeerSubtitle(_ peer: MdnsPeer) -> String {
        let host = peer.bestHost ?? peer.hostName ?? "unresolved"
        let state = peer.stale ? "last seen" : "available"
        return "\(peer.os) \(peer.version) · \(host):\(peer.port) · \(state)"
    }

    private var selectedPeer: MdnsPeer? {
        store.discoveredPeers.first { !$0.stale && !$0.publicKeyFingerprint.isEmpty && $0.publicKeyFingerprint != "dev" }
            ?? store.discoveredPeers.first { !$0.publicKeyFingerprint.isEmpty && $0.publicKeyFingerprint != "dev" }
            ?? store.discoveredPeers.first
    }

    @ViewBuilder
    private func trustBadge(for peer: MdnsPeer) -> some View {
        let state = store.trustState(peer: peer)
        Text(trustLabel(state))
            .font(.caption.weight(.semibold))
            .foregroundStyle(trustTint(state))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(trustTint(state).opacity(0.12), in: Capsule())
    }

    private func trustLabel(_ state: PairingService.PeerTrustState) -> String {
        switch state {
        case .unknownKey: "No key"
        case .unpaired: "Unpaired"
        case .trusted: "Trusted"
        case .keyChanged: "Key changed"
        }
    }

    private func trustTint(_ state: PairingService.PeerTrustState) -> Color {
        switch state {
        case .trusted: VisionPalette.mint
        case .unknownKey, .unpaired: VisionPalette.amber
        case .keyChanged: VisionPalette.red
        }
    }

    private func isKeyChanged(_ state: PairingService.PeerTrustState) -> Bool {
        if case .keyChanged = state { return true }
        return false
    }

    private func fingerprintRow(title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .frame(width: 110, alignment: .leading)
                .font(.callout)
            Text(shortFingerprint(value))
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(value)
            Spacer()
        }
    }

    private func shortFingerprint(_ fingerprint: String) -> String {
        let trimmed = fingerprint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 20 else { return trimmed.isEmpty ? "none" : trimmed }
        return "\(trimmed.prefix(10))...\(trimmed.suffix(8))"
    }

    private func editableRow(title: String, placeholder: String, value: Binding<String>) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .frame(width: 110, alignment: .leading)
                .font(.callout)
            TextField(placeholder, text: value)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var pendingFeaturesNote: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Coming next", systemImage: "sparkles")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("• PIN-based pairing with key pinning\n• More than one remote peer")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VisionPalette.blue.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
