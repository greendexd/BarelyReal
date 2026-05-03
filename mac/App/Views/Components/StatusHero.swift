import SwiftUI

struct StatusHero: View {
    enum State {
        case idleSend
        case idleReceive
        case sending(peer: String, frames: Int)
        case receivingWaiting
        case receivingActive(frames: Int)

        var title: String {
            switch self {
            case .idleSend: "Ready to share with Windows"
            case .idleReceive: "Ready to receive from Windows"
            case .sending: "Sharing keyboard & mouse"
            case .receivingWaiting: "Waiting for Windows…"
            case .receivingActive: "Connected"
            }
        }

        var subtitle: String? {
            switch self {
            case .idleSend: "Move your cursor past the screen edge to control the other machine."
            case .idleReceive: "Listening for incoming keyboard & mouse."
            case .sending(let peer, _): peer
            case .receivingWaiting: "Make sure the Windows app is sending."
            case .receivingActive: "Receiving keyboard & mouse from Windows."
            }
        }

        var systemImage: String {
            switch self {
            case .idleSend: "arrow.up.right.circle"
            case .idleReceive: "arrow.down.left.circle"
            case .sending: "paperplane.fill"
            case .receivingWaiting: "antenna.radiowaves.left.and.right"
            case .receivingActive: "checkmark.circle.fill"
            }
        }

        var tint: Color {
            switch self {
            case .idleSend, .idleReceive: .secondary
            case .sending, .receivingActive: .green
            case .receivingWaiting: .orange
            }
        }

        var pulse: Bool {
            if case .receivingWaiting = self { return true }
            return false
        }
    }

    let state: State
    let isRunning: Bool
    let primaryAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .center, spacing: 18) {
                ZStack {
                    Circle()
                        .fill(state.tint.opacity(0.12))
                        .frame(width: 64, height: 64)
                    Image(systemName: state.systemImage)
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(state.tint)
                        .symbolRenderingMode(.hierarchical)
                        .symbolEffect(.pulse, options: .repeating, isActive: state.pulse)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(state.title)
                        .font(.title2.weight(.semibold))
                    if let subtitle = state.subtitle {
                        Text(subtitle)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button(action: primaryAction) {
                    Label(isRunning ? "Stop" : "Start", systemImage: isRunning ? "stop.fill" : "play.fill")
                        .frame(minWidth: 64)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .tint(isRunning ? .red : .accentColor)
                .keyboardShortcut(isRunning ? "k" : "k", modifiers: [.command])
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        )
    }
}
