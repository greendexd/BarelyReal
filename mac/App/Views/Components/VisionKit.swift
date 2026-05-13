import SwiftUI

enum VisionPalette {
    static let blue = ProductPalette.blue
    static let mint = ProductPalette.green
    static let amber = ProductPalette.amber
    static let red = ProductPalette.red
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
            .padding(.horizontal, 34)
            .padding(.vertical, 34)
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(ProductPalette.background)
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
                    .foregroundStyle(ProductPalette.text)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(ProductPalette.subtext)
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
        .background(ProductPalette.card,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(ProductPalette.border, lineWidth: 1)
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
                .foregroundStyle(ProductPalette.subtext)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(ProductPalette.text)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(ProductPalette.subtext)
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
            case .idle: ProductPalette.muted
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
                    .foregroundStyle(ProductPalette.subtext)
                Text(value)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(ProductPalette.text)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(minHeight: 62)
        .background(ProductPalette.cardElevated.opacity(0.82),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(ProductPalette.border, lineWidth: 1)
        )
    }
}

struct VisionDivider: View {
    var body: some View {
        Rectangle()
            .fill(ProductPalette.hairline)
            .frame(height: 1)
    }
}
