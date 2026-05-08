import BarelyRealCore
import SwiftUI

struct DevicesView: View {
    @ObservedObject var store: BarelyRealStore

    @Binding var peerHost: String
    @Binding var peerMac: String
    @Binding var peerBroadcast: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Devices")
                        .font(.title2.weight(.semibold))
                    Text("Arrange every monitor across this Mac and your Windows peer.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                deviceCard
                wakeOnLanCard

                pendingFeaturesNote
            }
            .padding(28)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var wakeOnLanCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "powerplug.fill")
                    .foregroundStyle(.orange)
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
        .padding(20)
        .background(Color(nsColor: .controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        )
    }

    private var deviceCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.12))
                        .frame(width: 48, height: 48)
                    Image(systemName: "pc")
                        .font(.title2)
                        .foregroundStyle(.blue)
                        .symbolRenderingMode(.hierarchical)
                }

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
                        .foregroundStyle(store.remoteScreensStale ? .orange : .secondary)
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

            Divider().padding(.vertical, 16)

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
        .padding(20)
        .background(Color(nsColor: .controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        )
    }

    private var discoveredPeersList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Discovered on LAN")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(store.discoveredPeers) { peer in
                HStack(spacing: 10) {
                    Image(systemName: peer.stale ? "wifi.exclamationmark" : "network")
                        .foregroundStyle(peer.stale ? .orange : .green)
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
        .background(Color.accentColor.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
