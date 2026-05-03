import SwiftUI

@main
struct BarelyRealApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = BarelyRealStore()

    var body: some Scene {
        WindowGroup("BarelyReal") {
            ContentView(store: store)
                .frame(minWidth: 880, minHeight: 600)
        }
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Show BarelyReal") {
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.windows.first?.makeKeyAndOrderFront(nil)
                }
                .keyboardShortcut("b", modifiers: [.command])
            }
        }
    }
}
