import AppKit
import Combine
import CoreAudio

/// Owns the polling loop and publishes the current readings.
///
/// Polling is deliberately lazy: a timer with a generous tolerance (so the CPU can coalesce
/// our wake-up with other work instead of waking the core on its own), plus event-driven
/// refreshes for the cases you'd actually notice — putting the buds in, waking the Mac, and
/// opening the menu.
///
/// Connect detection listens to CoreAudio's device list rather than IOBluetooth: AirPods show
/// up as an audio device the moment they connect, and unlike the Bluetooth APIs it costs no
/// privacy prompt. Nothing in this app triggers TCC at all.
@MainActor
final class BatteryMonitor: ObservableObject {

    @Published private(set) var devices: [PodsDevice] = []
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var isRefreshing = false

    /// The device the menu bar represents. First connected one, or the pinned address if set.
    var primary: PodsDevice? {
        if let pinned = pinnedAddress, let match = devices.first(where: { $0.address == pinned }) {
            return match
        }
        return devices.first
    }

    var pinnedAddress: String? {
        didSet { UserDefaults.standard.set(pinnedAddress, forKey: "pinnedAddress") }
    }

    /// Seconds between polls. Slower when nothing is connected — there is nothing to change.
    private var pollInterval: TimeInterval { devices.isEmpty ? 120 : 60 }

    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var audioListener: AudioObjectPropertyListenerBlock?

    init() {
        pinnedAddress = UserDefaults.standard.string(forKey: "pinnedAddress")
    }

    func start() {
        observeSystemEvents()
        refresh()
        scheduleTimer()
    }

    // MARK: - Refreshing

    func refresh() {
        guard refreshTask == nil else { return }
        isRefreshing = true

        refreshTask = Task { [weak self] in
            let result: Result<[PodsDevice], Error>
            do {
                // `system_profiler` is a subprocess; keep it off the main actor.
                result = .success(try await Task.detached(priority: .utility) {
                    try BatteryReader.read()
                }.value)
            } catch {
                result = .failure(error)
            }

            guard let self, !Task.isCancelled else { return }
            self.apply(result)
            self.refreshTask = nil
            self.isRefreshing = false
        }
    }

    private func apply(_ result: Result<[PodsDevice], Error>) {
        let hadDevices = !devices.isEmpty

        switch result {
        case .success(let found):
            devices = found
            lastError = nil
            lastUpdated = Date()
        case .failure(let error):
            lastError = String(describing: error)
        }

        // Connected/disconnected changes the poll interval, so re-arm the timer.
        if hadDevices != !devices.isEmpty { scheduleTimer() }
    }

    // MARK: - Scheduling

    private func scheduleTimer() {
        timer?.invalidate()

        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        // Lets macOS batch our wake-up with other timers instead of firing a core just for us.
        timer.tolerance = pollInterval * 0.25
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func observeSystemEvents() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }

        observeAudioDevices()
    }

    /// Fires whenever an audio device appears or disappears — which is exactly when AirPods
    /// connect or disconnect. No permission required.
    private func observeAudioDevices() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.refreshAfterConnectionChange() }
        }

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, listener
        )
        audioListener = listener
    }

    /// bluetoothd doesn't know the battery levels the instant the buds connect, so read twice:
    /// once for the disconnect case (immediate) and once after it has caught up.
    private func refreshAfterConnectionChange() {
        refresh()
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            self?.refresh()
        }
    }
}
