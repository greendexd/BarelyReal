import SwiftUI

struct DevicesView: View {
    @ObservedObject var store: BarelyRealStore

    @Binding var peerHost: String
    @Binding var peerWidth: Int
    @Binding var peerHeight: Int
    @Binding var peerSideRaw: String
    @Binding var peerMac: String
    @Binding var peerBroadcast: String

    private var peerSide: PeerSide { PeerSide(rawValue: peerSideRaw) ?? .left }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Devices")
                        .font(.title2.weight(.semibold))
                    Text("BarelyReal currently supports a single peer. Pairing & discovery are coming soon.")
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
                }

                Spacer()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Layout")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 16)
                LayoutCanvas(
                    peerSideRaw: $peerSideRaw,
                    peerWidth: peerWidth,
                    peerHeight: peerHeight,
                    macWidth: NSScreen.main?.frame.width ?? 1440,
                    macHeight: NSScreen.main?.frame.height ?? 900
                )
                Text("Drag the Windows screen to either side of your Mac.")
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

                HStack(alignment: .center, spacing: 12) {
                    Text("Display size")
                        .frame(width: 110, alignment: .leading)
                        .font(.callout)
                    HStack(spacing: 8) {
                        TextField("Width", value: $peerWidth, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 100)
                        Text("×").foregroundStyle(.secondary)
                        TextField("Height", value: $peerHeight, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 100)
                        Text("pixels")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
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
            Text("• mDNS auto-discovery\n• PIN-based pairing with key pinning\n• Multi-device support")
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
