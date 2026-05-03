import Foundation

/// Virtual coordinate space across all peers' screens. Decides ownership transfer at edges.
public struct ScreenRect: Equatable, Codable {
    public let peerId: String
    public let screenId: Int
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int

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
