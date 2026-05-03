import ApplicationServices
import AppKit

final class StatusItemController {
    private var statusItem: NSStatusItem?
    private var permissionStatusItem: NSMenuItem?

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.title = "BR"
            button.toolTip = "BarelyReal"
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "BarelyReal", action: nil, keyEquivalent: ""))
        let permissionStatus = NSMenuItem(title: permissionStatusTitle(), action: nil, keyEquivalent: "")
        menu.addItem(permissionStatus)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Show Window", action: #selector(showWindow), keyEquivalent: "b"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Open Accessibility Settings", action: #selector(openAccessibilitySettings), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Open Input Monitoring Settings", action: #selector(openInputMonitoringSettings), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Refresh Permissions", action: #selector(refreshPermissions), keyEquivalent: "r"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit BarelyReal", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        for menuItem in menu.items where menuItem.action != #selector(NSApplication.terminate(_:)) {
            menuItem.target = self
        }

        item.menu = menu
        self.statusItem = item
        self.permissionStatusItem = permissionStatus
    }

    @objc private func showWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }

    @objc private func openAccessibilitySettings() {
        openSystemSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    @objc private func openInputMonitoringSettings() {
        openSystemSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    @objc private func refreshPermissions() {
        permissionStatusItem?.title = permissionStatusTitle()
    }

    private func permissionStatusTitle() -> String {
        AXIsProcessTrusted()
            ? "Accessibility: granted"
            : "Accessibility: missing"
    }

    private func openSystemSettings(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
