import SwiftUI

/// Visual layout designer.
///
/// Renders two screens (this Mac + the Windows peer) sized proportionally to their pixel
/// dimensions. The user drags the peer rectangle horizontally; if it ends up to the left of the
/// Mac it snaps to `.left`, otherwise to `.right`.
struct LayoutCanvas: View {
    @Binding var peerSideRaw: String
    let peerWidth: Int
    let peerHeight: Int
    let macWidth: CGFloat
    let macHeight: CGFloat

    @State private var dragOffset: CGFloat = 0

    private var peerSide: PeerSide { PeerSide(rawValue: peerSideRaw) ?? .left }

    private var macAspect: CGFloat { max(macWidth / max(macHeight, 1), 0.5) }
    private var peerAspect: CGFloat { max(CGFloat(peerWidth) / max(CGFloat(peerHeight), 1), 0.5) }

    var body: some View {
        GeometryReader { geo in
            // Total horizontal pixels combining both screens.
            let totalPixels = macWidth + CGFloat(peerWidth)
            let canvasWidth = geo.size.width - 32
            let canvasHeight: CGFloat = 160

            // Scale so both screens fit; clamp height too.
            let widthScale = canvasWidth / totalPixels
            let heightScale = canvasHeight / max(macHeight, CGFloat(peerHeight))
            let scale = min(widthScale, heightScale, 0.4)

            let macW = macWidth * scale
            let macH = macHeight * scale
            let peerW = CGFloat(peerWidth) * scale
            let peerH = CGFloat(peerHeight) * scale

            let centerX = canvasWidth / 2 + 16
            let baselineY = (canvasHeight - 1) // align rectangles by their bottom

            // Mac stays centred. Peer rectangle drifts based on side & drag.
            let macFrame = CGRect(
                x: centerX - macW / 2,
                y: canvasHeight - macH,
                width: macW,
                height: macH
            )

            let peerCenterAtRest: CGFloat = peerSide == .left
                ? macFrame.minX - peerW / 2 - 8
                : macFrame.maxX + peerW / 2 + 8
            let peerCenter = peerCenterAtRest + dragOffset

            ZStack(alignment: .topLeading) {
                // Background mat
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(.quaternary, lineWidth: 1)
                    )

                // Floor line
                Rectangle()
                    .fill(.tertiary)
                    .frame(height: 1)
                    .frame(maxWidth: .infinity)
                    .position(x: canvasWidth / 2 + 16, y: baselineY + 8)

                // Mac screen
                ScreenChip(
                    title: "This Mac",
                    pixels: "\(Int(macWidth))×\(Int(macHeight))",
                    accent: .accentColor,
                    glyph: "laptopcomputer"
                )
                .frame(width: macFrame.width, height: macFrame.height)
                .position(x: macFrame.midX, y: macFrame.midY)

                // Peer screen
                ScreenChip(
                    title: "Windows",
                    pixels: "\(peerWidth)×\(peerHeight)",
                    accent: .blue,
                    glyph: "pc"
                )
                .frame(width: peerW, height: peerH)
                .position(x: peerCenter, y: macFrame.midY)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            dragOffset = value.translation.width
                        }
                        .onEnded { value in
                            let projectedCenter = peerCenterAtRest + value.translation.width
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                dragOffset = 0
                                peerSideRaw = (projectedCenter < macFrame.midX ? PeerSide.left : .right).rawValue
                            }
                        }
                )
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: peerSideRaw)
            }
            .frame(width: geo.size.width, height: canvasHeight + 16)
        }
        .frame(height: 180)
    }
}

private struct ScreenChip: View {
    let title: String
    let pixels: String
    let accent: Color
    let glyph: String

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LinearGradient(
                    colors: [accent.opacity(0.18), accent.opacity(0.10)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(accent.opacity(0.45), lineWidth: 1.2)
                )

            Image(systemName: glyph)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(accent.opacity(0.55))
                .symbolRenderingMode(.hierarchical)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.semibold))
                Text(pixels)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 6)
        }
        .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
    }
}
