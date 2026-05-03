import Foundation

/// Virtual coordinate space across all peers' screens. Decides ownership transfer at edges.
public struct ScreenRect: Equatable, Codable {
    public let peerId: String
    public let screenId: Int
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int

    private enum CodingKeys: String, CodingKey {
        case peerId = "peer_id"
        case screenId = "screen_id"
        case x
        case y
        case width = "w"
        case height = "h"
    }

    public init(peerId: String, screenId: Int, x: Int, y: Int, width: Int, height: Int) {
        self.peerId = peerId
        self.screenId = screenId
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var maxX: Int { x + width }
    public var maxY: Int { y + height }

    public func contains(virtualX: Int, virtualY: Int) -> Bool {
        return virtualX >= x && virtualX < maxX && virtualY >= y && virtualY < maxY
    }
}

public struct Layout: Equatable, Codable {
    public var screens: [ScreenRect]
    public init(screens: [ScreenRect]) {
        self.screens = screens
    }

    public func screens(peerId: String) -> [ScreenRect] {
        screens.filter { $0.peerId == peerId }
    }

    public func screen(at x: Int, _ y: Int) -> ScreenRect? {
        screens.first { $0.contains(virtualX: x, virtualY: y) }
    }

    public func bounds(peerId: String? = nil) -> ScreenRectBounds? {
        let candidates = peerId.map { screens(peerId: $0) } ?? screens
        guard let first = candidates.first else { return nil }
        return candidates.dropFirst().reduce(ScreenRectBounds(first)) { $0.union($1) }
    }

    public func translated(peerId: String, dx: Int, dy: Int) -> Layout {
        Layout(screens: screens.map { screen in
            guard screen.peerId == peerId else { return screen }
            return ScreenRect(
                peerId: screen.peerId,
                screenId: screen.screenId,
                x: screen.x + dx,
                y: screen.y + dy,
                width: screen.width,
                height: screen.height
            )
        })
    }
}

public struct ScreenRectBounds: Equatable {
    public let minX: Int
    public let minY: Int
    public let maxX: Int
    public let maxY: Int

    public init(minX: Int, minY: Int, maxX: Int, maxY: Int) {
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }

    public init(_ screen: ScreenRect) {
        self.init(minX: screen.x, minY: screen.y, maxX: screen.maxX, maxY: screen.maxY)
    }

    public var width: Int { maxX - minX }
    public var height: Int { maxY - minY }
    public var midX: Int { (minX + maxX) / 2 }
    public var midY: Int { (minY + maxY) / 2 }

    public func union(_ screen: ScreenRect) -> ScreenRectBounds {
        ScreenRectBounds(
            minX: min(minX, screen.x),
            minY: min(minY, screen.y),
            maxX: max(maxX, screen.maxX),
            maxY: max(maxY, screen.maxY)
        )
    }
}

public final class LayoutEngine {
    public private(set) var layout: Layout

    public init(layout: Layout = Layout(screens: [])) {
        self.layout = layout
    }

    /// Given a global virtual point, return the screen that owns it (if any).
    public func screen(at x: Int, _ y: Int) -> ScreenRect? {
        return layout.screens.first { $0.contains(virtualX: x, virtualY: y) }
    }

    public func update(_ layout: Layout) {
        self.layout = layout
    }
}
