import Foundation
import Sparkle

@MainActor
final class UpdaterService: ObservableObject {
    let isAvailable: Bool
    private let controller: SPUStandardUpdaterController?

    init() {
        let controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        do {
            try controller.updater.start()
            self.controller = controller
            self.isAvailable = true
        } catch {
            self.controller = nil
            self.isAvailable = false
            NSLog("[CXSwitch] Sparkle updater disabled: %@", error.localizedDescription)
        }
    }

    var canCheckForUpdates: Bool {
        controller?.updater.canCheckForUpdates ?? false
    }

    func checkForUpdates() {
        guard let controller else {
            return
        }

        controller.checkForUpdates(nil)
    }
}
