import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: BarelyRealStore

    @Binding var controlPort: Int
    @Binding var kmPort: Int
    @Binding var clipboardPort: Int
    @Binding var scrollSpeed: Int
    @Binding var lockOnDisconnect: Bool
    @Binding var kmSharedSecret: String

    var body: some View {
        VisionPage(
            title: "Systems",
            subtitle: "Transport, input feel, permissions, and safety controls.",
            systemImage: "gearshape.fill"
        ) {
            section(title: "Network", icon: "network") {
                settingRow("Control port") {
                    TextField("24800", value: $controlPort, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 110)
                }
                settingRow("Keyboard & mouse port") {
                    TextField("24801", value: $kmPort, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 110)
                }
                settingRow("Clipboard port") {
                    TextField("24802", value: $clipboardPort, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 110)
                }
            }

            section(title: "Input feel", icon: "cursorarrow.motionlines") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Slider(
                            value: scrollSpeedDoubleBinding,
                            in: 1...20,
                            step: 1
                        )
                        Text("\(scrollSpeed)")
                            .font(.system(.callout, design: .monospaced))
                            .frame(width: 32, alignment: .trailing)
                    }
                    Text("Default 7. Lower values soften wheel events.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            section(title: "Privacy & safety", icon: "lock.shield") {
                VStack(alignment: .leading, spacing: 8) {
                    settingRow("KM shared secret") {
                        SecureField("Same secret on both computers", text: $kmSharedSecret)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 260)
                    }
                    Text("HMAC guard for dev UDP frames until TLS pairing lands.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VisionDivider()

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "keyboard")
                            .foregroundStyle(.secondary)
                        Text("Emergency return to Mac")
                            .font(.callout.weight(.medium))
                        Spacer()
                        Text("⌃⌥⌘Esc")
                            .font(.system(.callout, design: .monospaced).weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color(nsColor: .separatorColor).opacity(0.25),
                                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                }

                VisionDivider()

                Toggle(isOn: $lockOnDisconnect) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Lock display when KM link drops")
                        Text("Receive mode safety")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: lockOnDisconnect) { _, value in
                    store.setLockOnDisconnect(value)
                }
            }

            section(title: "Permissions", icon: "hand.raised") {
                permissionRow(name: "Accessibility",
                              granted: store.accessibilityGranted,
                              optional: false,
                              open: store.openAccessibilitySettings)
                permissionRow(name: "Input Monitoring",
                              granted: store.inputMonitoringGranted,
                              optional: true,
                              open: store.openInputMonitoringSettings)

                HStack(spacing: 8) {
                    Button("Refresh", systemImage: "arrow.clockwise", action: store.refreshPermissions)
                    Button("Request Input Monitoring", action: store.requestInputMonitoring)
                    Spacer()
                    Button(role: .destructive, action: store.resetBarelyRealPermissions) {
                        Text("Reset")
                    }
                }
                .controlSize(.small)
            }
        }
    }

    private var scrollSpeedDoubleBinding: Binding<Double> {
        Binding(
            get: { Double(scrollSpeed) },
            set: { scrollSpeed = min(max(Int($0.rounded()), 1), 20) }
        )
    }

    private func section<Content: View>(title: String,
                                        icon: String,
                                        @ViewBuilder content: @escaping () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VisionSectionTitle(title, systemImage: icon)
            VisionCard {
                content()
            }
        }
    }

    private func settingRow<Content: View>(_ title: String,
                                           @ViewBuilder accessory: () -> Content) -> some View {
        HStack {
            Text(title)
                .font(.callout)
            Spacer()
            accessory()
        }
    }

    private func permissionRow(name: String, granted: Bool, optional: Bool, open: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : (optional ? "info.circle.fill" : "exclamationmark.circle.fill"))
                .foregroundStyle(granted ? VisionPalette.mint : (optional ? .secondary : VisionPalette.amber))
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.callout)
                if optional && !granted {
                    Text("Optional. Start can still use Accessibility capture.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(granted ? "Granted" : (optional ? "Optional" : "Missing"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Open") { open() }
                .buttonStyle(.borderless)
                .controlSize(.small)
        }
    }
}
