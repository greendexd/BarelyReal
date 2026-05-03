import SwiftUI

/// Thin wrapper kept for compatibility with `BarelyRealApp`.
struct ContentView: View {
    @ObservedObject var store: BarelyRealStore

    var body: some View {
        RootView(store: store)
    }
}
