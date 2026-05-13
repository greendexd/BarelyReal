import SwiftUI

struct ActivityView: View {
    @ObservedObject var store: BarelyRealStore

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VisionGlyphBadge(systemImage: "waveform", tint: VisionPalette.blue, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Telemetry")
                        .font(.title2.weight(.semibold))
                    Text("Sanitized runtime events")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Export Diagnostics", systemImage: "square.and.arrow.up", action: store.exportDiagnostics)
                    .controlSize(.small)
                Text("\(store.logLines.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 14)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if store.logLines.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "tray")
                                    .font(.largeTitle)
                                    .foregroundStyle(ProductPalette.subtext)
                                Text("No events yet")
                                    .font(.callout)
                                    .foregroundStyle(ProductPalette.subtext)
                                Text("Start a session and you'll see traffic here.")
                                    .font(.caption)
                                    .foregroundStyle(ProductPalette.muted)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                        } else {
                            ForEach(Array(store.logLines.enumerated()), id: \.offset) { index, line in
                                EventRow(line: line)
                                    .background(index.isMultiple(of: 2)
                                                ? Color.clear
                                                : ProductPalette.card.opacity(0.45))
                                    .id(index)
                            }
                        }
                    }
                }
                .onChange(of: store.logLines.count) { _, count in
                    guard count > 0 else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(count - 1, anchor: .bottom)
                    }
                }
            }
        }
        .background(ProductPalette.background)
    }
}
