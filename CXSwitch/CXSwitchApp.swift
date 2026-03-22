import SwiftUI
import Sparkle

@main
struct CXSwitchApp: App {
    @State private var state = AppState()
    private let updaterService = UpdaterService()

    var body: some Scene {
        MenuBarExtra("CX", systemImage: "bolt.circle") {
            MenuBarView()
                .environment(state)
                .environmentObject(updaterService)
        }
        .menuBarExtraStyle(.window)
        // NOTE: When moving to an Xcode project, set LSUIElement = true in Info.plist
        // to hide the Dock icon (menubar-only behavior).
    }
}
