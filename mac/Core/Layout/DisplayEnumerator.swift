import AppKit
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

    public var screenRect: ScreenRect {
        ScreenRect(peerId: peerId, screenId: screenId, x: x, y: y, width: width, height: height)
    }
}

public enum DisplayEnumerator {
    public static func localDisplays(peerId: String = Host.current().localizedName ?? "mac") -> [DisplayInfo] {
        let primaryFrame = NSScreen.screens.first?.frame
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
                isPrimary: primaryFrame == frame
            )
        }
    }

    public static func localLayout(peerId: String = Host.current().localizedName ?? "mac") -> Layout {
        Layout(screens: localDisplays(peerId: peerId).map(\.screenRect))
    }
}
