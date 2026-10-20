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
        VStack(alignment: .leading, spacing: 14) {
            header

            if let device = monitor.primary {
                readings(for: device)
            } else {
                empty
            }

            Divider()
            settings
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 292)
        .onAppear {
            launchStatus = SMAppService.mainApp.status
            monitor.refreshIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            launchStatus = SMAppService.mainApp.status
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(monitor.primary?.name ?? "PodsBar")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 6) {
                    Circle()
                        .fill(isLive ? Color.green : Color.secondary)
                        .frame(width: 6, height: 6)
                    Text(status)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: monitor.refresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .disabled(monitor.isRefreshing)
            .help("Refresh now")
            .accessibilityLabel("Refresh now")
        }
    }

    /// Green only while we're showing fresh readings from a connected device.
    private var isLive: Bool { monitor.primary != nil && monitor.lastError == nil }

    private var status: String {
        isLive ? "Connected · \(freshness)" : freshness
    }

    // MARK: - Readings

    private func readings(for device: PodsDevice) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if device.isSingleCell {
                    BatteryTile(label: "Battery", level: device.single)
                } else {
                    BatteryTile(label: "Left", level: device.left)
                    BatteryTile(label: "Right", level: device.right)
                    BatteryTile(label: "Case", level: device.caseLevel, isCase: true)
                }
            }

            if let note = lowNote(for: device) {
                Notice(systemImage: "exclamationmark.triangle", text: note, tint: .red)
            }

            if let error = monitor.lastError {
                Notice(systemImage: "info.circle", text: "Showing last known levels. \(error)", tint: .secondary)
            }
        }
    }

    private func lowNote(for device: PodsDevice) -> String? {
        let buds = device.isSingleCell ? [("Battery", device.single)] : [("Left bud", device.left), ("Right bud", device.right)]
        let low = buds.compactMap { name, level in level.map { (name, $0) } }
            .filter { $0.1 <= MenuBarIcon.lowThreshold }
        switch low.count {
        case 0: return nil
        case 1: return "\(low[0].0) is at \(low[0].1)%. Charge it soon."
        default: return "Both buds are low. Charge them soon."
        }
    }

    private var empty: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(0..<2, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(.secondary, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                        .frame(width: 22, height: 48)
                }
            }
            .padding(.bottom, 4)
            .accessibilityHidden(true)

            Text(monitor.lastError == nil ? "No AirPods connected" : "Couldn't read battery levels")
                .font(.system(size: 13, weight: .semibold))
            Text(monitor.lastError ?? "Connect your AirPods to see battery levels.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .padding(.horizontal, 16)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.05)))
    }

    // MARK: - Settings

    private var settings: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Show in menu bar")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Picker("Show in menu bar", selection: $displayModeRaw) {
                    ForEach(DisplayMode.allCases) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            if monitor.devices.count > 1 || monitor.pinnedAddress != nil {
                HStack {
                    Text("Device")
                        .font(.system(size: 13))
                    Spacer()
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
                    .labelsHidden()
                    .controlSize(.small)
                    .fixedSize()
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                SettingSwitch(title: "Launch at login", isOn: Binding(
                    get: { launchStatus == .enabled || launchStatus == .requiresApproval },
                    set: setLaunchAtLogin
                ))

                if launchStatus == .requiresApproval {
                    Button("Allow in System Settings…") {
                        SMAppService.openSystemSettingsLoginItems()
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
                }

                if let launchError {
                    Text(launchError)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                SettingSwitch(title: "Check for updates automatically", isOn: Binding(
                    get: { updates.automaticallyChecksForUpdates },
                    set: updates.setAutomaticallyChecksForUpdates
                ))
                .disabled(updates.startupError != nil)

                if let error = updates.startupError {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 2) {
            Button(action: updates.checkForUpdates) {
                HStack {
                    Text("Check for Updates…")
                    Spacer()
                    if let version {
                        Text("v\(version)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .disabled(!updates.canCheckForUpdates)

            Button { NSApp.terminate(nil) } label: {
                HStack {
                    Text("Quit PodsBar")
                    Spacer()
                    Text("⌘Q")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .keyboardShortcut("q")
        }
        .buttonStyle(MenuRowButtonStyle())
        .padding(.horizontal, -6)
        .padding(.top, -4)
        .padding(.bottom, -6)
    }

    private var version: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    private var freshness: String {
        if monitor.isRefreshing { return "Refreshing…" }
        guard let updated = monitor.lastUpdated else { return "Never updated" }
        return "Updated \(updated.formatted(date: .omitted, time: .shortened))"
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

/// One battery as a tile: a capsule that fills from the bottom, the percentage, and a label.
/// The capsule echoes the menu bar glyph so the two read as the same thing.
private struct BatteryTile: View {
    let label: String
    let level: Int?
    var isCase = false

    var body: some View {
        VStack(spacing: 6) {
            cell
                .frame(height: 48, alignment: .bottom)

            Text(level.map { "\($0)%" } ?? "—")
                .font(.system(size: 22, weight: .semibold).monospacedDigit())
                .foregroundStyle(level == nil ? Color.secondary : tint)
                .padding(.top, 4)

            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.05)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(level.map { "\($0)%" } ?? "Not reported")
    }

    private var isLow: Bool { level.map { $0 <= MenuBarIcon.lowThreshold } ?? false }
    private var tint: Color { isLow ? .red : .primary }

    private var cell: some View {
        let width: CGFloat = isCase ? 34 : 22
        let height: CGFloat = isCase ? 40 : 48
        let radius: CGFloat = isCase ? 10 : 11
        // 1.5pt border plus 2.5pt of air between the outline and the fill.
        let inset: CGFloat = 4

        return ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(isLow ? Color.red : Color.primary.opacity(level == nil ? 0.25 : 0.45), lineWidth: 1.5)

            if let level {
                // Keep a sliver visible at very low levels, as the menu bar glyph does.
                let fraction = CGFloat(max(8, min(level, 100))) / 100
                RoundedRectangle(cornerRadius: radius - 3, style: .continuous)
                    .fill(tint)
                    .frame(height: (height - inset * 2) * fraction)
                    .padding(inset)
            }
        }
        .frame(width: width, height: height)
    }
}

private struct Notice: View {
    let systemImage: String
    let text: String
    let tint: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .medium))
            Text(text)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(tint.opacity(0.1)))
    }
}

/// A full-width row: title on the left, switch on the right.
private struct SettingSwitch: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 13))
            Spacer()
            Toggle(title, isOn: $isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
        .frame(minHeight: 26)
    }
}

/// Buttons that look like menu items: full width, highlighted on hover.
private struct MenuRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Row(configuration: configuration)
    }

    private struct Row: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 13))
                .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(highlight))
                )
                .onHover { hovering = $0 }
        }

        private var highlight: Double {
            guard isEnabled, hovering else { return 0 }
            return configuration.isPressed ? 0.16 : 0.09
        }
    }
}
