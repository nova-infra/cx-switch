import SwiftUI

@main
struct CXSwitchApp: App {
    @State private var state = AppState()

    var body: some Scene {
        MenuBarExtra("CX", systemImage: "bolt.circle") {
            MenuBarView()
                .environment(state)
        }
        .menuBarExtraStyle(.window)
        // NOTE: When moving to an Xcode project, set LSUIElement = true in Info.plist
        // to hide the Dock icon (menubar-only behavior).
    }
}
