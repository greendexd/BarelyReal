import SwiftUI

enum VisionPalette {
    static let blue = Color(red: 0.16, green: 0.46, blue: 0.96)
    static let mint = Color(red: 0.08, green: 0.62, blue: 0.48)
    static let amber = Color(red: 0.95, green: 0.58, blue: 0.18)
    static let red = Color(red: 0.86, green: 0.20, blue: 0.25)
}

struct VisionPage<Content: View>: View {
    let title: String
    let subtitle: String
    var systemImage: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VisionHeader(title: title, subtitle: subtitle, systemImage: systemImage)
                content()
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }
}

struct VisionHeader: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VisionGlyphBadge(systemImage: systemImage, tint: VisionPalette.blue, size: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.title2.weight(.semibold))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
    }
}

struct VisionCard<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            content()
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        )
    }
}

struct VisionSectionTitle: View {
    let title: String
    let subtitle: String?
    let systemImage: String

    init(_ title: String, subtitle: String? = nil, systemImage: String) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
        }
    }
}

struct VisionGlyphBadge: View {
    let systemImage: String
    var tint: Color = VisionPalette.blue
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tint.opacity(0.14))
                .frame(width: size, height: size)
            Image(systemName: systemImage)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(tint)
                .symbolRenderingMode(.hierarchical)
        }
        .frame(width: size, height: size)
    }
}

struct VisionStatusDot: View {
    enum Kind {
        case idle
        case active
        case warning
        case danger

        var color: Color {
            switch self {
            case .idle: .secondary
            case .active: VisionPalette.mint
            case .warning: VisionPalette.amber
            case .danger: VisionPalette.red
            }
        }
    }

    let kind: Kind

    var body: some View {
        Circle()
            .fill(kind.color)
            .frame(width: 8, height: 8)
            .shadow(color: kind.color.opacity(kind == .idle ? 0 : 0.35), radius: 3)
    }
}

struct VisionMetricTile: View {
    let title: String
    let value: String
    let systemImage: String
    var tint: Color = VisionPalette.blue

    var body: some View {
        HStack(spacing: 10) {
            VisionGlyphBadge(systemImage: systemImage, tint: tint, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(minHeight: 62)
        .background(Color(nsColor: .separatorColor).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct VisionDivider: View {
    var body: some View {
        Rectangle()
            .fill(.quaternary)
            .frame(height: 1)
    }
}
