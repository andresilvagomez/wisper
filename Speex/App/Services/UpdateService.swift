import Foundation
import Sparkle

@MainActor
final class UpdateService: NSObject, ObservableObject {
    private let updaterController: SPUStandardUpdaterController

    @Published var canCheckForUpdates = false

    override init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()

        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)

        // Check automatically every 4 hours
        updaterController.updater.updateCheckInterval = 4 * 60 * 60
        updaterController.updater.automaticallyChecksForUpdates = true
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}
