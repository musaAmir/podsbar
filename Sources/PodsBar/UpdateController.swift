import AppKit
import Combine
import Sparkle

/// Sparkle owns the update schedule and installer; no app-specific polling loop is needed.
@MainActor
final class UpdateController: NSObject, ObservableObject, @preconcurrency SPUStandardUserDriverDelegate {
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false
    @Published private(set) var startupError: String?

    var willPresentUI: (() -> Void)?
    private var controller: SPUStandardUpdaterController?

    func start() {
        guard controller == nil else { return }
        do {
            try UpdateConfiguration.validate(Bundle.main.infoDictionary ?? [:])
            let controller = SPUStandardUpdaterController(
                startingUpdater: false, updaterDelegate: nil, userDriverDelegate: self
            )
            try controller.updater.start()
            self.controller = controller
            controller.updater.publisher(for: \.canCheckForUpdates)
                .removeDuplicates()
                .receive(on: RunLoop.main)
                .assign(to: &$canCheckForUpdates)
            controller.updater.publisher(for: \.automaticallyChecksForUpdates)
                .removeDuplicates()
                .receive(on: RunLoop.main)
                .assign(to: &$automaticallyChecksForUpdates)
            startupError = nil
        } catch {
            // A malformed local build should not interrupt battery monitoring with an alert.
            startupError = error.localizedDescription
        }
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        willPresentUI?()
        NSApp.activate()
        controller?.checkForUpdates(nil)
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        controller?.updater.automaticallyChecksForUpdates = enabled
    }

    func standardUserDriverWillShowModalAlert() { willPresentUI?() }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        if handleShowingUpdate { willPresentUI?() }
    }
}

enum UpdateConfiguration {
    enum Failure: LocalizedError {
        case invalidFeed
        case invalidKey

        var errorDescription: String? {
            switch self {
            case .invalidFeed: return "This build needs a valid HTTPS update feed."
            case .invalidKey: return "This build needs a valid Sparkle public signing key."
            }
        }
    }

    static func validate(_ info: [String: Any]) throws {
        guard let value = info["SUFeedURL"] as? String, let url = URL(string: value),
              url.scheme == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.fragment == nil else {
            throw Failure.invalidFeed
        }
        guard let value = info["SUPublicEDKey"] as? String,
              let key = Data(base64Encoded: value), key.count == 32 else {
            throw Failure.invalidKey
        }
    }
}
