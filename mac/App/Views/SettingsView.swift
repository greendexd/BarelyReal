import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: BarelyRealStore

    @Binding var controlPort: Int
    @Binding var kmPort: Int
    @Binding var clipboardPort: Int
    @Binding var scrollSpeed: Int
    @Binding var lockOnDisconnect: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Settings")
                        .font(.title2.weight(.semibold))
                    Text("Advanced controls. Defaults work for most setups.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

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
                        Text("Scroll wheel sensitivity. Default 7 feels natural; higher values are faster.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                section(title: "Privacy & safety", icon: "lock.shield") {
                    Toggle(isOn: $lockOnDisconnect) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Lock display when KM link drops")
                            Text("Triggers after 5 seconds of silence in receive mode.")
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
                                  open: store.openAccessibilitySettings)
                    permissionRow(name: "Input Monitoring",
                                  granted: store.inputMonitoringGranted,
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
            .padding(28)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var scrollSpeedDoubleBinding: Binding<Double> {
        Binding(
            get: { Double(scrollSpeed) },
            set: { scrollSpeed = min(max(Int($0.rounded()), 1), 20) }
        )
    }

    private func section<Content: View>(title: String,
                                        icon: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 14) {
                content()
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.quaternary, lineWidth: 1)
            )
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

    private func permissionRow(name: String, granted: Bool, open: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(granted ? .green : .orange)
            Text(name)
                .font(.callout)
            Spacer()
            Text(granted ? "Granted" : "Missing")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Open") { open() }
                .buttonStyle(.borderless)
                .controlSize(.small)
        }
    }
}
