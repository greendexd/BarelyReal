import Foundation

public struct ScreenAnnouncement: Codable, Equatable {
    public let peerId: String
    public let screens: [AnnouncedScreen]

    public init(peerId: String, screens: [AnnouncedScreen]) {
        self.peerId = peerId
        self.screens = screens
    }

    private enum CodingKeys: String, CodingKey {
        case peerId = "peer_id"
        case screens
    }
}

public struct AnnouncedScreen: Codable, Equatable {
    public let id: Int
    public let x: Int
    public let y: Int
    public let w: Int
    public let h: Int
    public let scale: Double
    public let primary: Bool

    public init(id: Int, x: Int, y: Int, w: Int, h: Int, scale: Double, primary: Bool) {
        self.id = id
        self.x = x
        self.y = y
        self.w = w
        self.h = h
        self.scale = scale
        self.primary = primary
    }

    public init(display: DisplayInfo) {
        self.init(
            id: display.screenId,
            x: display.x,
            y: display.y,
            w: display.width,
            h: display.height,
            scale: display.scale,
            primary: display.isPrimary
        )
    }

    public func displayInfo(peerId: String) -> DisplayInfo {
        DisplayInfo(peerId: peerId, screenId: id, x: x, y: y, width: w, height: h, scale: scale, isPrimary: primary)
    }
}

public struct LayoutSyncMessage: Codable, Equatable {
    public let layout: [ScreenRect]

    public init(layout: [ScreenRect]) {
        self.layout = layout
    }
}

public struct HelloMessage: Codable, Equatable {
    public let name: String
    public let os: String
    public let ver: String
    public let screens: [AnnouncedScreen]

    public init(name: String, os: String, ver: String, screens: [AnnouncedScreen]) {
        self.name = name
        self.os = os
        self.ver = ver
        self.screens = screens
    }
}
