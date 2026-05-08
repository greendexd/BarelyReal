import BarelyRealCore
import SwiftUI

/// Multi-monitor layout editor for the current two-peer dev mode.
struct LayoutCanvas: View {
    let layout: BarelyRealCore.Layout
    let localPeerId: String
    let remotePeerId: String
    let remoteIsStale: Bool
    let onMoveRemote: (_ dx: Int, _ dy: Int, _ snap: Bool) -> Void

    @State private var dragPixels: CGSize = .zero

    private var localScreens: [ScreenRect] { layout.screens(peerId: localPeerId) }
    private var remoteScreens: [ScreenRect] { layout.screens(peerId: remotePeerId) }
    var body: some View {
        GeometryReader { geo in
            let canvas = CGSize(width: geo.size.width, height: 260)
            let bounds = editorBounds()
            let scale = min(
                (canvas.width - 44) / CGFloat(max(bounds.width, 1)),
                (canvas.height - 44) / CGFloat(max(bounds.height, 1))
            )
            let dragDx = Int((dragPixels.width / max(scale, 0.001)).rounded())
            let dragDy = Int((dragPixels.height / max(scale, 0.001)).rounded())
            let previewLayout = layout
                .translated(peerId: remotePeerId, dx: dragDx, dy: dragDy)
                .stickySnapped(peerId: remotePeerId, toPeerId: localPeerId)
            let previewRemoteScreens = remoteScreens.isEmpty ? [] : previewLayout.screens(peerId: remotePeerId)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(.quaternary, lineWidth: 1)
                    )

                grid(in: canvas)

                ForEach(localScreens, id: \.screenId) { screen in
                    screenChip(screen, title: screenTitle(screen, fallback: "Mac"), accent: .accentColor, glyph: "display")
                        .frame(width: CGFloat(screen.width) * scale, height: CGFloat(screen.height) * scale)
                        .position(position(for: screen, in: canvas, bounds: bounds, scale: scale))
                }

                ForEach(previewRemoteScreens, id: \.screenId) { screen in
                    screenChip(screen, title: screenTitle(screen, fallback: "Windows"), accent: remoteIsStale ? .orange : .blue, glyph: "pc")
                        .frame(width: CGFloat(screen.width) * scale, height: CGFloat(screen.height) * scale)
                        .position(position(for: screen, in: canvas, bounds: bounds, scale: scale))
                }

                if remoteScreens.isEmpty {
                    emptyRemoteState
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .gesture(remoteDrag(scale: scale))
            .clipped()
        }
        .frame(height: 260)
    }

    private func remoteDrag(scale: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard !remoteScreens.isEmpty else { return }
                dragPixels = value.translation
            }
            .onEnded { value in
                guard !remoteScreens.isEmpty else { return }
                let dx = Int((value.translation.width / max(scale, 0.001)).rounded())
                let dy = Int((value.translation.height / max(scale, 0.001)).rounded())
                dragPixels = .zero
                onMoveRemote(dx, dy, true)
            }
    }

    private func editorBounds() -> ScreenRectBounds {
        let fallback = ScreenRectBounds(minX: 0, minY: 0, maxX: 1440, maxY: 900)
        let local = BarelyRealCore.Layout(screens: localScreens).bounds() ?? fallback
        let remote = BarelyRealCore.Layout(screens: remoteScreens).bounds()

        let remoteWidth = max(remote?.width ?? 1440, 640)
        let remoteHeight = max(remote?.height ?? 900, 480)
        let padX = max(max(local.width, remoteWidth) / 3, 280)
        let padY = max(max(local.height, remoteHeight) / 3, 220)

        return ScreenRectBounds(
            minX: local.minX - remoteWidth - padX,
            minY: local.minY - remoteHeight - padY,
            maxX: local.maxX + remoteWidth + padX,
            maxY: local.maxY + remoteHeight + padY
        )
    }

    private func position(for screen: ScreenRect, in canvas: CGSize, bounds: ScreenRectBounds, scale: CGFloat) -> CGPoint {
        let x = CGFloat(screen.x - bounds.minX) * scale + CGFloat(screen.width) * scale / 2 + 22
        let y = CGFloat(screen.y - bounds.minY) * scale + CGFloat(screen.height) * scale / 2 + 22
        return CGPoint(x: x, y: y)
    }

    private func screenChip(_ screen: ScreenRect, title: String, accent: Color, glyph: String) -> some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(accent.opacity(0.13))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(accent.opacity(0.55), lineWidth: 1.2)
                )

            Image(systemName: glyph)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(accent.opacity(0.62))
                .symbolRenderingMode(.hierarchical)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text("\(screen.width)×\(screen.height)  \(screen.x),\(screen.y)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 6)
        }
        .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
    }

    private func screenTitle(_ screen: ScreenRect, fallback: String) -> String {
        "\(fallback) \(screen.screenId)"
    }

    private var emptyRemoteState: some View {
        VStack(spacing: 8) {
            Image(systemName: "display.trianglebadge.exclamationmark")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Waiting for Windows screens")
                .font(.callout.weight(.semibold))
            Text("Start BarelyReal on Windows with the same control port.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func grid(in canvas: CGSize) -> some View {
        Canvas { context, size in
            var path = Path()
            let spacing: CGFloat = 32
            var x: CGFloat = 0
            while x <= size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += spacing
            }
            var y: CGFloat = 0
            while y <= size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += spacing
            }
            context.stroke(path, with: .color(.secondary.opacity(0.08)), lineWidth: 1)
        }
        .frame(width: canvas.width, height: canvas.height)
    }
}
