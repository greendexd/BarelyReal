import SwiftUI

struct PermissionBanner: View {
    let accessibilityGranted: Bool
    let inputMonitoringGranted: Bool
    let onOpenAccessibility: () -> Void
    let onOpenInputMonitoring: () -> Void
    let onRefresh: () -> Void

    private var hasIssue: Bool { !accessibilityGranted }

    var body: some View {
        if hasIssue {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                    .symbolRenderingMode(.hierarchical)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Accessibility required")
                        .font(.headline)
                    Text(missingDescription)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        Button("Open Accessibility", action: onOpenAccessibility)
                            .controlSize(.small)
                        Button("Refresh", systemImage: "arrow.clockwise", action: onRefresh)
                            .controlSize(.small)
                            .labelStyle(.iconOnly)
                    }
                    .padding(.top, 2)
                }

                Spacer()
            }
            .padding(16)
            .background(VisionPalette.amber.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(VisionPalette.amber.opacity(0.28), lineWidth: 1)
            )
        }
    }

    private var missingDescription: String {
        "BarelyReal needs Accessibility access to capture and release keyboard/mouse control. Input Monitoring is optional in this dev build."
    }
}
