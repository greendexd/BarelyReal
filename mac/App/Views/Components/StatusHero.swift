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
            case .idleSend: "Handoff armed"
            case .idleReceive: "Receiver armed"
            case .sending: "Handoff active"
            case .receivingWaiting: "Awaiting peer"
            case .receivingActive: "Connected"
            }
        }

        var subtitle: String? {
            switch self {
            case .idleSend: "Mac controls Windows"
            case .idleReceive: "Windows controls Mac"
            case .sending(let peer, _): peer
            case .receivingWaiting: "Receiver online"
            case .receivingActive: "Windows input accepted"
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
            case .sending, .receivingActive: VisionPalette.mint
            case .receivingWaiting: VisionPalette.amber
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
        VisionCard(padding: 22) {
            HStack(alignment: .center, spacing: 18) {
                VisionGlyphBadge(systemImage: state.systemImage, tint: state.tint, size: 58)
                    .symbolEffect(.pulse, options: .repeating, isActive: state.pulse)

                VStack(alignment: .leading, spacing: 4) {
                    Text(state.title)
                        .font(.system(size: 25, weight: .semibold))
                    if let subtitle = state.subtitle {
                        Text(subtitle)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button(action: primaryAction) {
                    Label(isRunning ? "Stop" : "Start", systemImage: isRunning ? "stop.fill" : "play.fill")
                        .frame(minWidth: 80)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .tint(isRunning ? VisionPalette.red : VisionPalette.blue)
                .keyboardShortcut(isRunning ? "k" : "k", modifiers: [.command])
            }
        }
    }
}
