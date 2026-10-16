import Combine
import ServiceManagement
import SwiftUI

struct PopoverView: View {
    @ObservedObject var monitor: BatteryMonitor
    @ObservedObject var updates: UpdateController
    @AppStorage("displayMode") private var displayModeRaw = DisplayMode.podsAndBoth.rawValue

    @State private var launchStatus = SMAppService.mainApp.status
    @State private var launchError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let device = monitor.primary {
                readings(for: device)
            } else {
                empty
            }

            Divider().padding(.vertical, 8)
            controls
        }
        .padding(12)
        .frame(width: 244)
        .onAppear {
            launchStatus = SMAppService.mainApp.status
            monitor.refreshIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            launchStatus = SMAppService.mainApp.status
        }
    }

    // MARK: - Readings

    private func readings(for device: PodsDevice) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(device.name)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)

            VStack(spacing: 7) {
                if device.isSingleCell {
                    BatteryRow(label: "Battery", level: device.single)
                } else {
                    BatteryRow(label: "Left", level: device.left)
                    BatteryRow(label: "Right", level: device.right)
                }
                if !device.isSingleCell {
                    BatteryRow(label: "Case", level: device.caseLevel)
                }
            }
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(monitor.lastError == nil ? "No AirPods connected" : "Couldn't read battery levels")
                .font(.system(size: 13, weight: .semibold))
            Text(monitor.lastError ?? "Connect your AirPods to see battery levels.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            if monitor.devices.count > 1 || monitor.pinnedAddress != nil {
                Picker("Device", selection: Binding(
                    get: { monitor.pinnedAddress ?? "" },
                    set: { monitor.pinnedAddress = $0.isEmpty ? nil : $0 }
                )) {
                    Text("Automatic").tag("")
                    if let pinned = monitor.pinnedAddress,
                       !monitor.devices.contains(where: { $0.address == pinned }) {
                        Text("Preferred device (disconnected)").tag(pinned)
                    }
                    ForEach(monitor.devices) { device in
                        Text(device.name).tag(device.address)
                    }
                }
                .pickerStyle(.menu)
                .controlSize(.small)
            }

            HStack {
                Text(freshness)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: monitor.refresh) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(monitor.isRefreshing)
                .help("Refresh now")
            }

            if let error = monitor.lastError, monitor.primary != nil {
                Text("Showing last known levels. \(error)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Picker("Menu bar", selection: $displayModeRaw) {
                ForEach(DisplayMode.allCases) { mode in
                    Text(mode.label).tag(mode.rawValue)
                }
            }
            .pickerStyle(.menu)
            .controlSize(.small)

            Toggle("Launch at login", isOn: Binding(
                get: { launchStatus == .enabled || launchStatus == .requiresApproval },
                set: setLaunchAtLogin
            ))
                .toggleStyle(.checkbox)
                .controlSize(.small)

            if launchStatus == .requiresApproval {
                Button("Allow in System Settings…") {
                    SMAppService.openSystemSettingsLoginItems()
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11))
            }

            if let launchError {
                Text(launchError)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            Button("Check for Updates…", action: updates.checkForUpdates)
                .buttonStyle(.borderless)
                .disabled(!updates.canCheckForUpdates)

            Toggle("Check for updates automatically", isOn: Binding(
                get: { updates.automaticallyChecksForUpdates },
                set: updates.setAutomaticallyChecksForUpdates
            ))
            .toggleStyle(.checkbox)
            .controlSize(.small)
            .disabled(updates.startupError != nil)

            if let error = updates.startupError {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button("Quit PodsBar") { NSApp.terminate(nil) }
                .buttonStyle(.borderless)
                .keyboardShortcut("q")
        }
    }

    private var freshness: String {
        if monitor.isRefreshing { return "Refreshing…" }
        guard let updated = monitor.lastUpdated else { return "Never updated" }
        return "Updated at \(updated.formatted(date: .omitted, time: .shortened))"
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchError = nil
        } catch {
            launchError = "Couldn't change this: \(error.localizedDescription)"
        }
        launchStatus = SMAppService.mainApp.status
    }
}

private struct BatteryRow: View {
    let label: String
    let level: Int?

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .leading)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(color)
                        .frame(width: geometry.size.width * CGFloat(level ?? 0) / 100)
                }
            }
            .frame(height: 5)

            Text(level.map { "\($0)%" } ?? "—")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .frame(width: 34, alignment: .trailing)
                .foregroundStyle(level == nil ? .secondary : .primary)
        }
    }

    private var color: Color {
        guard let level else { return .clear }
        return level <= MenuBarIcon.lowThreshold ? .red : .primary
    }
}
