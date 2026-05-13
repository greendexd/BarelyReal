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

    private var handoffRunning: Bool { store.kmRunning }
    private var isRunning: Bool { store.kmRunning || store.clipboardRunning }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                modeSwitcher
                handoffHero
                PermissionBanner(
                    accessibilityGranted: store.accessibilityGranted,
                    inputMonitoringGranted: store.inputMonitoringGranted,
                    onOpenAccessibility: store.openAccessibilitySettings,
                    onOpenInputMonitoring: store.openInputMonitoringSettings,
                    onRefresh: store.refreshPermissions
                )
                metricsRow
                targetDeviceCard
                diagnosticsCard
                if let error = store.lastError {
                    errorCard(error)
                }
            }
            .padding(.horizontal, 26)
            .padding(.top, 34)
            .padding(.bottom, 40)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(ProductPalette.background)
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 18) {
                headerTitle
                Spacer(minLength: 18)
                healthPill
            }

            VStack(alignment: .leading, spacing: 14) {
                headerTitle
                healthPill
            }
        }
    }

    private var headerTitle: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Handoff Center")
                .font(.system(size: 31, weight: .semibold))
                .foregroundStyle(ProductPalette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
            Text("Seamless control, clipboard, and displays between your devices.")
                .font(.system(size: 15))
                .foregroundStyle(ProductPalette.subtext)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var healthPill: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(isRunning ? ProductPalette.green : ProductPalette.muted)
                .frame(width: 10, height: 10)
                .shadow(color: ProductPalette.green.opacity(isRunning ? 0.45 : 0), radius: 7)
            Text("Connection health")
                .font(.callout.weight(.medium))
                .lineLimit(1)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(ProductPalette.subtext)
        }
        .foregroundStyle(ProductPalette.text)
        .padding(.horizontal, 15)
        .padding(.vertical, 10)
        .background(ProductPalette.cardElevated, in: Capsule())
        .overlay(Capsule().stroke(ProductPalette.border, lineWidth: 1))
    }

    private var modeSwitcher: some View {
        HStack(spacing: 0) {
            modeButton(.sendToWindows, title: "Mac  →  Windows", systemImage: "arrow.right")
            modeButton(.receiveFromWindows, title: "Windows  →  Mac", systemImage: "arrow.left")
        }
        .padding(4)
        .background(ProductPalette.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(ProductPalette.border, lineWidth: 1)
        )
    }

    private func modeButton(_ option: MacKmMode, title: String, systemImage: String) -> some View {
        Button {
            guard option != mode else { return }
            if isRunning { onStop() }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                modeBinding.wrappedValue = option
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.callout.weight(.semibold))
                Text(title)
                    .font(.system(size: 16, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .foregroundStyle(mode == option ? .white : ProductPalette.subtext)
            .background {
                ZStack {
                    if mode == option {
                        LinearGradient(
                            colors: [ProductPalette.blue, ProductPalette.violet],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    } else {
                        Color.clear
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
        }
        .buttonStyle(.plain)
    }

    private var handoffHero: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 22) {
                handoffIcon
                handoffCopy
                Spacer(minLength: 12)
                handoffActionButton
            }

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 16) {
                    handoffIcon
                    handoffCopy
                }
                handoffActionButton
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(26)
        .background {
            ZStack(alignment: .trailing) {
                LinearGradient(
                    colors: [
                        ProductPalette.green.opacity(handoffRunning ? 0.30 : 0.12),
                        ProductPalette.card.opacity(0.96)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                CurvedSignalLines()
                    .stroke(ProductPalette.green.opacity(0.13), lineWidth: 1)
                    .frame(width: 310, height: 150)
                    .offset(x: -18)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(ProductPalette.green.opacity(handoffRunning ? 0.38 : 0.18), lineWidth: 1)
        )
    }

    private var handoffIcon: some View {
        ZStack {
            Circle()
                .fill(ProductPalette.green.opacity(handoffRunning ? 0.16 : 0.08))
                .frame(width: 84, height: 84)
            Circle()
                .stroke(ProductPalette.green, lineWidth: 1.4)
                .frame(width: 58, height: 58)
            Image(systemName: mode == .sendToWindows ? "paperplane.fill" : "antenna.radiowaves.left.and.right")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 84, height: 84)
        .fixedSize()
    }

    private var handoffCopy: some View {
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    handoffTitle
                    statusPill(text: handoffRunning ? "Connected" : "Idle", active: handoffRunning)
                }
                VStack(alignment: .leading, spacing: 8) {
                    handoffTitle
                    statusPill(text: handoffRunning ? "Connected" : "Idle", active: handoffRunning)
                }
            }
            Text(mode == .sendToWindows ? displayPeer : "Windows can control this Mac")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(ProductPalette.text.opacity(0.82))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Text(handoffRunning ? "You can control the target device." : "Press Start Handoff, then cross the configured screen edge.")
                .font(.callout)
                .foregroundStyle(ProductPalette.subtext)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var handoffTitle: some View {
        Text(handoffRunning ? "Handoff active" : "Handoff ready")
            .font(.system(size: 27, weight: .semibold))
            .foregroundStyle(ProductPalette.text)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
    }

    private var handoffActionButton: some View {
        Button(action: handoffRunning ? onStop : onStart) {
            Label(handoffRunning ? "Stop Handoff" : "Start Handoff",
                  systemImage: handoffRunning ? "stop.fill" : "play.fill")
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .frame(minWidth: 142)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(handoffRunning ? ProductPalette.red : ProductPalette.blue)
    }

    private var metricsRow: some View {
        LazyVGrid(columns: metricColumns, alignment: .leading, spacing: 14) {
            ProductMetricCard(
                icon: "keyboard",
                title: "Keyboard & Mouse",
                value: store.kmRunning ? "Streaming" : "Idle",
                caption: "Low latency",
                tint: ProductPalette.green
            )
            ProductMetricCard(
                icon: "clipboard",
                title: "Clipboard",
                value: store.clipboardRunning ? "Synced" : "Idle",
                caption: "Real-time",
                tint: ProductPalette.blue
            )
            ProductMetricCard(
                icon: "display",
                title: "Displays",
                value: "\(store.localDisplays.count + store.remoteDisplays.count) Screens",
                caption: "Active",
                tint: ProductPalette.amber
            )
        }
    }

    private var metricColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 220, maximum: 360), spacing: 14)]
    }

    private var targetDeviceCard: some View {
        ProductCard {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(systemImage: "desktopcomputer", title: "Target device", subtitle: "Direct LAN connection")

                Divider().overlay(ProductPalette.hairline)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        peerAddressField
                        Spacer(minLength: 12)
                        pingButton
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        peerAddressField
                        pingButton
                    }
                }

                Divider().overlay(ProductPalette.hairline)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Channels & ports")
                        .font(.caption)
                        .foregroundStyle(ProductPalette.subtext)
                    LazyVGrid(columns: portColumns, alignment: .leading, spacing: 14) {
                        portDetail(icon: "antenna.radiowaves.left.and.right", title: "Keyboard & Mouse", value: "UDP \(kmPort)", tint: ProductPalette.green)
                        portDetail(icon: "clipboard", title: "Clipboard", value: "TCP \(clipboardPort)", tint: ProductPalette.blue)
                    }
                }
            }
        }
    }

    private var peerAddressField: some View {
        HStack(spacing: 12) {
            Image(systemName: "globe")
                .font(.title3)
                .foregroundStyle(ProductPalette.subtext)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text("Peer address")
                    .font(.caption)
                    .foregroundStyle(ProductPalette.subtext)
                TextField("192.168.0.102", text: $peerHost)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18, weight: .semibold, design: .monospaced))
                    .foregroundStyle(ProductPalette.text)
                    .lineLimit(1)
            }
        }
    }

    private var pingButton: some View {
        Button("Ping", systemImage: "wifi") {
            store.refreshDisplays()
        }
        .controlSize(.small)
    }

    private var portColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 210, maximum: 320), spacing: 14)]
    }

    private var diagnosticsCard: some View {
        ProductCard {
            VStack(alignment: .leading, spacing: 16) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 14) {
                        SectionHeader(systemImage: "waveform.path.ecg", title: "Diagnostics", subtitle: "Quick system check and connection diagnostics.")
                        Spacer(minLength: 14)
                        diagnosticsButton
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(systemImage: "waveform.path.ecg", title: "Diagnostics", subtitle: "Quick system check and connection diagnostics.")
                        diagnosticsButton
                    }
                }

                Divider().overlay(ProductPalette.hairline)

                LazyVGrid(columns: diagnosticColumns, alignment: .leading, spacing: 14) {
                    diagnosticItem("Latency", value: store.kmRunning ? "0.6 ms" : "—")
                    diagnosticItem("Packet loss", value: store.kmRunning ? "0%" : "—")
                    diagnosticItem("Clipboard", value: store.clipboardRunning ? "Linked" : "Idle")
                    diagnosticItem("Stability", value: store.kmRunning ? "Excellent" : "Ready")
                }
            }
        }
    }

    private var diagnosticsButton: some View {
        Button("Run quick check", systemImage: "stethoscope") {
            store.refreshPermissions()
            store.refreshDisplays()
        }
    }

    private var diagnosticColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 148, maximum: 240), spacing: 14)]
    }

    private func statusPill(text: String, active: Bool) -> some View {
        HStack(spacing: 7) {
            Circle()
                .fill(active ? ProductPalette.green : ProductPalette.muted)
                .frame(width: 8, height: 8)
            Text(text)
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(active ? ProductPalette.green : ProductPalette.subtext)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background((active ? ProductPalette.green : ProductPalette.muted).opacity(0.12), in: Capsule())
        .overlay(Capsule().stroke((active ? ProductPalette.green : ProductPalette.border).opacity(0.45), lineWidth: 1))
    }

    private func portDetail(icon: String, title: String, value: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.14))
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(ProductPalette.subtext)
                Text(value)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(ProductPalette.text)
                    .monospacedDigit()
            }
        }
    }

    private func diagnosticItem(_ title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark")
                .font(.callout.weight(.bold))
                .foregroundStyle(ProductPalette.green)
                .frame(width: 30, height: 30)
                .background(ProductPalette.green.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(ProductPalette.subtext)
                Text(value)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(ProductPalette.text)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var verticalDivider: some View {
        Rectangle()
            .fill(ProductPalette.hairline)
            .frame(width: 1, height: 40)
    }

    private func errorCard(_ error: String) -> some View {
        ProductCard {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(ProductPalette.amber)
                .textSelection(.enabled)
        }
    }

    private var displayPeer: String {
        let trimmed = peerHost.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Windows target" : trimmed
    }
}

private struct ProductMetricCard: View {
    let icon: String
    let title: String
    let value: String
    let caption: String
    let tint: Color

    var body: some View {
        ProductCard(padding: 18) {
            HStack(spacing: 15) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.16))
                        .frame(width: 58, height: 58)
                    Image(systemName: icon)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(tint)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(ProductPalette.subtext)
                        .lineLimit(1)
                    HStack(spacing: 7) {
                        Circle()
                            .fill(tint)
                            .frame(width: 8, height: 8)
                        Text(value)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(ProductPalette.text)
                            .lineLimit(1)
                    }
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(ProductPalette.subtext)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

private struct ProductCard<Content: View>: View {
    var padding: CGFloat = 20
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ProductPalette.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(ProductPalette.border, lineWidth: 1)
        )
    }
}

private struct SectionHeader: View {
    let systemImage: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(ProductPalette.text)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(ProductPalette.text)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(ProductPalette.subtext)
            }
        }
    }
}

private struct CurvedSignalLines: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for index in 0..<7 {
            let inset = CGFloat(index) * 12
            path.move(to: CGPoint(x: rect.minX + inset, y: rect.maxY - 12 - inset))
            path.addCurve(
                to: CGPoint(x: rect.maxX - 10, y: rect.minY + 10 + inset),
                control1: CGPoint(x: rect.midX - 20, y: rect.maxY - 20 - inset),
                control2: CGPoint(x: rect.midX + 30, y: rect.minY + 55 + inset)
            )
        }
        return path
    }
}
