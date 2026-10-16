import AppKit
import Combine
import CoreAudio

/// One scan at a time, infrequent polling, and coalesced connection/wake refreshes.
@MainActor
final class BatteryMonitor: ObservableObject {
    @Published private(set) var devices: [PodsDevice] = []
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var isRefreshing = false
    @Published var pinnedAddress: String? {
        didSet { defaults.set(pinnedAddress, forKey: "pinnedAddress") }
    }

    var primary: PodsDevice? {
        if let pinned = pinnedAddress,
           let match = devices.first(where: { $0.address == pinned }) {
            return match
        }
        // Prefer a wearable with bud readings over a case-only Bluetooth record.
        return devices.first(where: { $0.left != nil || $0.right != nil || $0.single != nil }) ?? devices.first
    }

    private let defaults: UserDefaults
    private let read: () async throws -> [PodsDevice]
    private let connectionDelay: Duration
    private var pollInterval: TimeInterval { devices.isEmpty ? 120 : 60 }
    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var connectionTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var audioListener: AudioObjectPropertyListenerBlock?
    private var started = false
    private var sleeping = false
    private var refreshGeneration = 0
    private var needsRefresh = false

    init(defaults: UserDefaults = .standard,
         read: @escaping () async throws -> [PodsDevice] = BatteryReader.read,
         connectionDelay: Duration = .seconds(4)) {
        self.defaults = defaults
        self.read = read
        self.connectionDelay = connectionDelay
        pinnedAddress = defaults.string(forKey: "pinnedAddress").map(BatteryReader.normalizeAddress)
    }

    func start() {
        guard !started else { return }
        started = true
        sleeping = false
        observeSystemEvents()
        refresh()
    }

    /// Explicit shutdown also removes observers; repeated view appearances cannot add more.
    func stop() {
        started = false
        suspend()
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers.removeAll()
        if let audioListener {
            var address = Self.audioDevicesAddress
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, audioListener
            )
            self.audioListener = nil
        }
    }

    /// Opening the popover can reuse a recent scan. The refresh button always forces a scan.
    func refreshIfNeeded(maxAge: TimeInterval = 15) {
        if lastError == nil, let lastUpdated, Date().timeIntervalSince(lastUpdated) < maxAge { return }
        refresh()
    }

    func refresh() {
        guard !sleeping, refreshTask == nil else { return }
        timer?.invalidate()
        timer = nil
        isRefreshing = true
        refreshGeneration += 1
        let generation = refreshGeneration
        let read = self.read

        refreshTask = Task { [weak self] in
            let result: Result<[PodsDevice], Error>
            do {
                result = .success(try await read())
            } catch {
                result = .failure(error)
            }

            guard let self, !Task.isCancelled, self.refreshGeneration == generation else { return }
            switch result {
            case .success(let found):
                // Avoid publishing an unchanged array on every poll.
                if self.devices != found { self.devices = found }
                self.lastError = nil
                self.lastUpdated = Date()
            case .failure(let error):
                self.lastError = error.localizedDescription
            }
            self.refreshTask = nil
            self.isRefreshing = false
            if self.needsRefresh {
                self.needsRefresh = false
                self.refresh()
            } else {
                self.scheduleTimer()
            }
        }
    }

    // A one-shot timer is armed after completion, so a slow scan cannot stack up polls.
    private func scheduleTimer() {
        timer?.invalidate()
        guard started, !sleeping else { timer = nil; return }
        let timer = Timer(timeInterval: pollInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer.tolerance = pollInterval * 0.25
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func suspend() {
        sleeping = true
        timer?.invalidate()
        timer = nil
        connectionTask?.cancel()
        connectionTask = nil
        refreshGeneration += 1
        refreshTask?.cancel()
        refreshTask = nil
        needsRefresh = false
        isRefreshing = false
    }

    func resume() {
        sleeping = false
        refreshAfterConnectionChange()
    }

    /// The immediate read handles disconnects. One delayed read lets bluetoothd catch up;
    /// replacing it coalesces bursts of CoreAudio events into a single follow-up.
    func refreshAfterConnectionChange() {
        guard !sleeping else { return }
        refreshIfNeeded(maxAge: 2)
        connectionTask?.cancel()
        let delay = connectionDelay
        connectionTask = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard let self, !Task.isCancelled else { return }
            self.connectionTask = nil
            if self.refreshTask != nil {
                self.needsRefresh = true
            } else {
                self.refresh()
            }
        }
    }

    private func observeSystemEvents() {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.started else { return }
                self.suspend()
            }
        })
        observers.append(center.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.started else { return }
                self.resume()
            }
        })

        var address = Self.audioDevicesAddress
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in
                guard let self, self.started else { return }
                self.refreshAfterConnectionChange()
            }
        }
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, listener
        )
        if status == noErr { audioListener = listener }
        // If registration fails, the normal polling timer still updates the readings.
    }

    private static var audioDevicesAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }
}
