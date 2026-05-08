import AppKit
import BarelyRealCore
import SwiftUI

struct ClipboardHistoryView: View {
    @ObservedObject var store: BarelyRealStore

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .medium
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VisionGlyphBadge(systemImage: "doc.on.clipboard", tint: VisionPalette.mint, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Clipboard")
                        .font(.title2.weight(.semibold))
                    Text("\(store.clipboardEntries.count) recent shared items")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Refresh", systemImage: "arrow.clockwise", action: store.loadClipboardHistory)
                    .controlSize(.small)
                    .labelStyle(.iconOnly)
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 14)

            Divider()

            ScrollView {
                if store.clipboardEntries.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No clipboard items yet")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text("Copy something on either machine — items will appear here.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(store.clipboardEntries.enumerated()), id: \.offset) { _, entry in
                            HistoryRow(entry: entry)
                        }
                    }
                    .padding(20)
                }
            }
        }
        .background(Color(nsColor: .underPageBackgroundColor))
        .onAppear { store.loadClipboardHistory() }
    }
}

private struct HistoryRow: View {
    let entry: ClipboardEntry

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            iconBadge

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(kindLabel)
                        .font(.callout.weight(.semibold))
                    Text(formattedDate)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(byteSize)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                preview
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var preview: some View {
        if let text = textPreview {
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .truncationMode(.tail)
                .textSelection(.enabled)
        } else if let imageData = entry.formats["image/png"], let image = NSImage(data: imageData) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: 120)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else if let json = entry.formats["application/x-barelyreal-files"] {
            Text(filesPreview(from: json))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var iconBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tint.opacity(0.15))
                .frame(width: 36, height: 36)
            Image(systemName: glyph)
                .foregroundStyle(tint)
                .font(.system(size: 16, weight: .semibold))
        }
    }

    private var kindLabel: String {
        if entry.formats["text/plain"] != nil { return "Text" }
        if entry.formats["image/png"] != nil  { return "Image" }
        if entry.formats["application/x-barelyreal-files"] != nil { return "Files" }
        return "Item"
    }

    private var glyph: String {
        if entry.formats["text/plain"] != nil { return "text.alignleft" }
        if entry.formats["image/png"] != nil  { return "photo" }
        if entry.formats["application/x-barelyreal-files"] != nil { return "doc.on.doc" }
        return "doc"
    }

    private var tint: Color {
        if entry.formats["text/plain"] != nil { return .blue }
        if entry.formats["image/png"] != nil  { return .pink }
        if entry.formats["application/x-barelyreal-files"] != nil { return .green }
        return .secondary
    }

    private var formattedDate: String {
        let date = Date(timeIntervalSince1970: TimeInterval(entry.id) / 1000)
        return ClipboardHistoryView.dateFormatter.string(from: date)
    }

    private var byteSize: String {
        let total = entry.formats.values.reduce(0) { $0 + $1.count }
        return ByteCountFormatter().string(fromByteCount: Int64(total))
    }

    private var textPreview: String? {
        guard let data = entry.formats["text/plain"] else { return nil }
        let raw = String(data: data, encoding: .utf8) ?? ""
        return raw.isEmpty ? nil : raw
    }

    private func filesPreview(from json: Data) -> String {
        struct Summary: Codable { let names: [String] }
        if let s = try? JSONDecoder().decode(Summary.self, from: json) {
            return s.names.prefix(4).joined(separator: ", ")
        }
        return "Files (\(json.count) bytes)"
    }
}
