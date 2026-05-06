import AppKit
import IOKit.hid

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        statusItem = StatusItemController()
        statusItem?.install()
        requestInputMonitoringIfNeeded()
    }

    private func requestInputMonitoringIfNeeded() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeUnknown else { return }
            IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }
    }
}
