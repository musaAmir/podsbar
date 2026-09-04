import SwiftUI

@main
struct PodsBarApp: App {
    @StateObject private var monitor = BatteryMonitor()
    @AppStorage("displayMode") private var displayModeRaw = DisplayMode.podsAndBoth.rawValue

    var body: some Scene {
        MenuBarExtra {
            PopoverView(monitor: monitor)
        } label: {
            Image(nsImage: menuBarImage)
                .onAppear { monitor.start() }
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarImage: NSImage {
        let mode = DisplayMode(rawValue: displayModeRaw) ?? .podsAndBoth
        guard let device = monitor.primary else { return MenuBarIcon.disconnected() }
        return MenuBarIcon.image(for: device, mode: mode)
    }
}
