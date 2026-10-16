import AppKit
import Combine
import SwiftUI

@main
@MainActor
enum PodsBarApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = PodsBarDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

/// AppKit owns the tiny always-visible status item. SwiftUI is only instantiated when
/// the popover opens, and its view graph is released again when the popover closes.
@MainActor
private final class PodsBarDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let monitor = BatteryMonitor()
    private let updates = UpdateController()
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var keyMonitor: Any?
    private var subscriptions: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        statusItem = item
        // Handle the app shortcut locally without constructing an otherwise unused menu.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
            if modifiers == .command, event.charactersIgnoringModifiers == "q" {
                NSApp.terminate(nil)
                return nil
            }
            return event
        }

        monitor.$devices.combineLatest(monitor.$pinnedAddress)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatus() }
            .store(in: &subscriptions)
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatus()
            }
            .store(in: &subscriptions)
        monitor.start()
        updates.willPresentUI = { [weak self] in self?.popover?.performClose(nil) }
        updates.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
        subscriptions.removeAll()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
    }

    private func updateStatus() {
        let primary = monitor.primary
        let mode = DisplayMode(rawValue: UserDefaults.standard.string(forKey: "displayMode") ?? "") ?? .podsAndBoth
        statusItem?.button?.image = primary.map { MenuBarIcon.image(for: $0, mode: mode) }
            ?? MenuBarIcon.disconnected()
        let description = primary.map { "\($0.name) battery levels" } ?? "No AirPods connected"
        statusItem?.button?.toolTip = description
        statusItem?.button?.setAccessibilityLabel(description)
        if let primary {
            let readings = primary.isSingleCell ? [("Battery", primary.single)]
                : [("Left", primary.left), ("Right", primary.right), ("Case", primary.caseLevel)]
            statusItem?.button?.setAccessibilityValue(readings.map { label, level in
                "\(label): \(level.map { "\($0)%" } ?? "not reported")"
            }.joined(separator: ", "))
        } else {
            statusItem?.button?.setAccessibilityValue(nil)
        }
    }

    @objc private func togglePopover() {
        if let popover, popover.isShown {
            popover.performClose(nil)
            return
        }
        guard let button = statusItem?.button else { return }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: PopoverView(monitor: monitor, updates: updates))
        self.popover = popover
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate()
        popover.contentViewController?.view.window?.makeKey()
    }

    func popoverDidClose(_ notification: Notification) {
        guard let closed = notification.object as? NSPopover, closed === popover else { return }
        popover?.contentViewController = nil
        popover = nil
    }
}
