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

    public func stickySnapped(peerId movingPeerId: String, toPeerId anchorPeerId: String) -> Layout {
        guard let moving = bounds(peerId: movingPeerId) else { return self }
        let anchors = screens(peerId: anchorPeerId)
        guard !anchors.isEmpty else { return self }

        var best: SnapCandidate?
        for anchor in anchors.map(ScreenRectBounds.init) {
            for candidate in SnapCandidate.candidates(moving: moving, anchor: anchor) {
                if best == nil || candidate.score < best!.score {
                    best = candidate
                }
            }
        }

        guard let best else { return self }
        return translated(peerId: movingPeerId, dx: best.dx, dy: best.dy)
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

private struct SnapCandidate {
    let dx: Int
    let dy: Int
    let score: Int

    static func candidates(moving: ScreenRectBounds, anchor: ScreenRectBounds) -> [SnapCandidate] {
        let left = candidate(
            moving: moving,
            x: anchor.minX - moving.width,
            y: alignedStart(
                movingStart: moving.minY,
                movingEnd: moving.maxY,
                anchorStart: anchor.minY,
                anchorEnd: anchor.maxY,
                length: moving.height
            )
        )
        let right = candidate(
            moving: moving,
            x: anchor.maxX,
            y: alignedStart(
                movingStart: moving.minY,
                movingEnd: moving.maxY,
                anchorStart: anchor.minY,
                anchorEnd: anchor.maxY,
                length: moving.height
            )
        )
        let top = candidate(
            moving: moving,
            x: alignedStart(
                movingStart: moving.minX,
                movingEnd: moving.maxX,
                anchorStart: anchor.minX,
                anchorEnd: anchor.maxX,
                length: moving.width
            ),
            y: anchor.minY - moving.height
        )
        let bottom = candidate(
            moving: moving,
            x: alignedStart(
                movingStart: moving.minX,
                movingEnd: moving.maxX,
                anchorStart: anchor.minX,
                anchorEnd: anchor.maxX,
                length: moving.width
            ),
            y: anchor.maxY
        )
        return [left, right, top, bottom]
    }

    private static func candidate(moving: ScreenRectBounds, x: Int, y: Int) -> SnapCandidate {
        let dx = x - moving.minX
        let dy = y - moving.minY
        return SnapCandidate(dx: dx, dy: dy, score: abs(dx) + abs(dy))
    }

    private static func alignedStart(
        movingStart: Int,
        movingEnd: Int,
        anchorStart: Int,
        anchorEnd: Int,
        length: Int
    ) -> Int {
        let cornerSnap = 96
        if abs(movingStart - anchorStart) <= cornerSnap {
            return anchorStart
        }
        if abs(movingEnd - anchorEnd) <= cornerSnap {
            return anchorEnd - length
        }
        if movingEnd <= anchorStart {
            return anchorStart
        }
        if movingStart >= anchorEnd {
            return anchorEnd - length
        }
        return movingStart
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
