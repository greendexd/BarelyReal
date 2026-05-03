import SwiftUI

struct HomeView: View {
    @ObservedObject var store: BarelyRealStore

    @Binding var peerHost: String
    @Binding var modeRaw: String
    let kmPort: Int
    let clipboardPort: Int

    let onStart: () -> Void
    let onStop: () -> Void
    let onTestText: () -> Void
    let onTestImage: () -> Void

    private var mode: MacKmMode {
        MacKmMode(rawValue: modeRaw) ?? .sendToWindows
    }

    private var modeBinding: Binding<MacKmMode> {
        Binding(
            get: { mode },
            set: { modeRaw = $0.rawValue }
        )
    }

    private var heroState: StatusHero.State {
        switch (mode, store.kmRunning) {
        case (.sendToWindows, false):
            return .idleSend
        case (.sendToWindows, true):
            return .sending(peer: peerHost.isEmpty ? "Windows" : peerHost, frames: 0)
        case (.receiveFromWindows, false):
            return .idleReceive
        case (.receiveFromWindows, true):
            return store.receiverLinkUp
                ? .receivingActive(frames: 0)
                : .receivingWaiting
        }
    }

    private var isRunning: Bool { store.kmRunning || store.clipboardRunning }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ModeSwitcher(
                    mode: modeBinding,
                    isRunning: isRunning,
                    onModeWillChange: onStop
                )

                StatusHero(
                    state: heroState,
                    isRunning: isRunning,
                    primaryAction: {
                        if isRunning { onStop() } else { onStart() }
                    }
                )

                PermissionBanner(
                    accessibilityGranted: store.accessibilityGranted,
                    inputMonitoringGranted: store.inputMonitoringGranted,
                    onOpenAccessibility: store.openAccessibilitySettings,
                    onOpenInputMonitoring: store.openInputMonitoringSettings,
                    onRefresh: store.refreshPermissions
                )

                if mode == .sendToWindows {
                    SendQuickPanel(
                        peerHost: $peerHost,
                        kmPort: kmPort,
                        clipboardPort: clipboardPort
                    )
                } else {
                    ReceiveQuickPanel(
                        kmPort: kmPort,
                        clipboardPort: clipboardPort,
                        clipboardPeer: peerHost,
                        isRunning: store.kmRunning
                    )
                }

                if isRunning || !store.logLines.isEmpty {
                    QuickStatsRow(store: store, mode: mode)
                }

                ClipboardTestCard(
                    onTestText: onTestText,
                    onTestImage: onTestImage,
                    enabled: store.clipboardRunning || isRunning
                )

                if let error = store.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                        .padding(.top, 4)
                }
            }
            .padding(28)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct ModeSwitcher: View {
    @Binding var mode: MacKmMode
    let isRunning: Bool
    let onModeWillChange: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(MacKmMode.allCases) { option in
                Button {
                    guard option != mode else { return }
                    if isRunning {
                        onModeWillChange()
                    }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        mode = option
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: option == .sendToWindows ? "arrow.right" : "arrow.left")
                            .font(.callout.weight(.semibold))
                        Text(option == .sendToWindows ? "Mac → Windows" : "Windows → Mac")
                            .font(.callout.weight(.medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(
                        Group {
                            if mode == option {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(Color(nsColor: .controlBackgroundColor))
                                    .shadow(color: .black.opacity(0.08), radius: 3, x: 0, y: 1)
                            }
                        }
                    )
                    .foregroundStyle(mode == option ? Color.primary : Color.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color(nsColor: .controlColor).opacity(0.4),
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

private struct SendQuickPanel: View {
    @Binding var peerHost: String
    let kmPort: Int
    let clipboardPort: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "laptopcomputer")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Windows machine")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("192.168.0.102", text: $peerHost, prompt: Text("Windows IP address"))
                        .textFieldStyle(.plain)
                        .font(.title3.weight(.medium))
                }
                Spacer()
            }

            Divider()

            HStack(spacing: 18) {
                detail(icon: "antenna.radiowaves.left.and.right", title: "Keyboard & mouse", value: "UDP \(kmPort)")
                detail(icon: "doc.on.clipboard", title: "Clipboard", value: "TCP \(clipboardPort)")
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

    private func detail(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.callout.weight(.medium))
                    .monospacedDigit()
            }
        }
    }
}

private struct ReceiveQuickPanel: View {
    let kmPort: Int
    let clipboardPort: Int
    let clipboardPeer: String
    let isRunning: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .foregroundStyle(.secondary)
                Text("Listening on this Mac")
                    .font(.callout.weight(.medium))
                Spacer()
            }
            HStack(spacing: 18) {
                detail(icon: "keyboard", title: "Keyboard & mouse", value: "UDP \(kmPort)")
                detail(icon: "doc.on.clipboard", title: "Clipboard peer", value: clipboardPeer.isEmpty ? "—" : clipboardPeer)
            }

            Divider()

            Label(
                isRunning
                    ? "Now start Windows in “Windows → Mac” mode and enter this Mac IP there."
                    : "Press Start here first, then start Windows in “Windows → Mac” mode.",
                systemImage: isRunning ? "checkmark.circle" : "play.circle"
            )
            .font(.caption)
            .foregroundStyle(isRunning ? .green : .secondary)
        }
        .padding(20)
        .background(Color(nsColor: .controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        )
    }

    private func detail(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.callout.weight(.medium))
                    .monospacedDigit()
            }
        }
    }
}

private struct QuickStatsRow: View {
    @ObservedObject var store: BarelyRealStore
    let mode: MacKmMode

    var body: some View {
        HStack(spacing: 12) {
            StatPill(
                title: mode == .sendToWindows ? "KM stream" : "Receiving",
                value: store.kmRunning ? "Active" : "Idle",
                systemImage: "keyboard",
                tint: store.kmRunning ? .green : .secondary
            )

            StatPill(
                title: "Clipboard",
                value: store.clipboardRunning ? "Synced" : "Idle",
                systemImage: "doc.on.clipboard",
                tint: store.clipboardRunning ? .blue : .secondary
            )

            if mode == .receiveFromWindows {
                StatPill(
                    title: "Link",
                    value: !store.kmRunning ? "—" : (store.receiverLinkUp ? "Up" : "Down"),
                    systemImage: store.receiverLinkUp ? "checkmark.circle" : "xmark.circle",
                    tint: store.receiverLinkUp ? .green : .orange
                )
            }
        }
    }
}

private struct ClipboardTestCard: View {
    let onTestText: () -> Void
    let onTestImage: () -> Void
    let enabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "wand.and.stars")
                    .foregroundStyle(.secondary)
                Text("Test clipboard")
                    .font(.callout.weight(.semibold))
                Spacer()
            }
            Text("Send a test snippet to the peer to verify the clipboard channel.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button(action: onTestText) {
                    Label("Send text", systemImage: "text.alignleft")
                        .frame(maxWidth: .infinity)
                }
                Button(action: onTestImage) {
                    Label("Send image", systemImage: "photo")
                        .frame(maxWidth: .infinity)
                }
            }
            .controlSize(.regular)
            .disabled(!enabled)
        }
        .padding(18)
        .background(Color(nsColor: .controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        )
    }
}
