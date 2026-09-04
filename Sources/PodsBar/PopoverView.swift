import ServiceManagement
import SwiftUI

struct PopoverView: View {
    @ObservedObject var monitor: BatteryMonitor
    @AppStorage("displayMode") private var displayModeRaw = DisplayMode.podsAndBoth.rawValue

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchError: String?
    @State private var now = Date()

    private let ticker = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

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
        .onReceive(ticker) { now = $0 }
        .onAppear { monitor.refresh() }
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
                BatteryRow(label: "Case", level: device.caseLevel)
            }
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("No AirPods connected")
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

            Picker("Menu bar", selection: $displayModeRaw) {
                ForEach(DisplayMode.allCases) { mode in
                    Text(mode.label).tag(mode.rawValue)
                }
            }
            .pickerStyle(.menu)
            .controlSize(.small)

            Toggle("Launch at login", isOn: $launchAtLogin)
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }

            if let launchError {
                Text(launchError)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            Button("Quit PodsBar") { NSApp.terminate(nil) }
                .buttonStyle(.borderless)
                .keyboardShortcut("q")
        }
    }

    private var freshness: String {
        guard let updated = monitor.lastUpdated else { return "Never updated" }
        let seconds = Int(now.timeIntervalSince(updated))
        if seconds < 10 { return "Updated just now" }
        if seconds < 60 { return "Updated \(seconds)s ago" }
        return "Updated \(seconds / 60)m ago"
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
            // Unsigned local builds can't register; surface it instead of silently reverting.
            launchAtLogin = SMAppService.mainApp.status == .enabled
            launchError = "Couldn't change this: \(error.localizedDescription)"
        }
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
