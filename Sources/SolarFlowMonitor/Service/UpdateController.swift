import Foundation
import Sparkle

@MainActor
final class UpdateController: NSObject, ObservableObject, SPUUpdaterDelegate {
    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: self,
        userDriverDelegate: nil
    )
    private var configuredFeedURL: URL?

    @Published private(set) var isConfigured = false
    @Published private(set) var canCheckForUpdates = false

    func configure(feedURLString: String, automaticallyChecks: Bool) {
        let value = feedURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value), url.scheme == "https" else {
            isConfigured = false
            canCheckForUpdates = false
            return
        }
        configuredFeedURL = url
        controller.updater.automaticallyChecksForUpdates = automaticallyChecks
        do {
            try controller.updater.start()
            isConfigured = true
            canCheckForUpdates = controller.updater.canCheckForUpdates
        } catch {
            isConfigured = false
            canCheckForUpdates = false
        }
    }

    func checkForUpdates() {
        guard isConfigured else { return }
        controller.checkForUpdates(nil)
    }

    nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        MainActor.assumeIsolated { configuredFeedURL?.absoluteString }
    }
}
