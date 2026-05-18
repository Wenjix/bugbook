import Foundation
import Combine
import Sparkle

@MainActor
final class UpdaterService: ObservableObject {
    private var controller: SPUStandardUpdaterController?

    @Published private(set) var canCheckForUpdates = true

    func checkForUpdates() {
        configureControllerIfNeeded()
        guard canCheckForUpdates else { return }
        controller?.checkForUpdates(nil)
    }

    private func configureControllerIfNeeded() {
        guard controller == nil else { return }

        let controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.controller = controller
        canCheckForUpdates = controller.updater.canCheckForUpdates
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}
