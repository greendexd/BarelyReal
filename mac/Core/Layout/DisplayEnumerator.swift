import AppKit
import CoreGraphics
import Foundation

public struct DisplayInfo: Equatable, Codable {
    public let peerId: String
    public let screenId: Int
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int
    public let scale: Double
    public let isPrimary: Bool

    public init(peerId: String, screenId: Int, x: Int, y: Int, width: Int, height: Int, scale: Double, isPrimary: Bool) {
        self.peerId = peerId
        self.screenId = screenId
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.scale = scale
        self.isPrimary = isPrimary
    }

    public var screenRect: ScreenRect {
        ScreenRect(peerId: peerId, screenId: screenId, x: x, y: y, width: width, height: height)
    }
}

public enum DisplayEnumerator {
    public static func localDisplays(peerId: String = Host.current().localizedName ?? "mac") -> [DisplayInfo] {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        guard count > 0 else {
            return NSScreen.screens.enumerated().map { index, screen in
                let frame = screen.frame
                return DisplayInfo(
                    peerId: peerId,
                    screenId: screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? Int ?? index,
                    x: Int(frame.origin.x.rounded()),
                    y: Int(frame.origin.y.rounded()),
                    width: Int(frame.width.rounded()),
                    height: Int(frame.height.rounded()),
                    scale: Double(screen.backingScaleFactor),
                    isPrimary: screen == NSScreen.main
                )
            }
        }

        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &displays, &count)
        let scaleById = Dictionary(uniqueKeysWithValues: NSScreen.screens.compactMap { screen -> (Int, Double)? in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? Int else { return nil }
            return (id, Double(screen.backingScaleFactor))
        })

        return displays.map { display in
            let frame = CGDisplayBounds(display)
            let id = Int(display)
            return DisplayInfo(
                peerId: peerId,
                screenId: id,
                x: Int(frame.origin.x.rounded()),
                y: Int(frame.origin.y.rounded()),
                width: Int(frame.width.rounded()),
                height: Int(frame.height.rounded()),
                scale: scaleById[id] ?? 1.0,
                isPrimary: display == CGMainDisplayID()
            )
        }
    }

    public static func localLayout(peerId: String = Host.current().localizedName ?? "mac") -> Layout {
        Layout(screens: localDisplays(peerId: peerId).map(\.screenRect))
    }
}
