import Foundation

/// One AirPods-family device and whatever battery readings it exposes.
struct PodsDevice: Equatable, Identifiable {
    var id: String { address }

    var name: String
    var address: String
    var left: Int?
    var right: Int?
    var caseLevel: Int?
    /// Single-cell devices (AirPods Max, most Beats) report one level instead of L/R.
    var single: Int?

    /// What the menu bar shows when it only has room for one number.
    var headline: Int? {
        let buds = [left, right].compactMap { $0 }
        if !buds.isEmpty { return buds.min() }
        return single
    }

    var hasAnyReading: Bool {
        left != nil || right != nil || caseLevel != nil || single != nil
    }

    var isSingleCell: Bool { left == nil && right == nil && single != nil }
}

/// Reads AirPods battery levels from `system_profiler`.
///
/// macOS 26 no longer publishes `BatteryPercent*` keys in the IOKit registry, which is
/// what older menu bar apps read. `bluetoothd` is now the only source, and
/// `system_profiler SPBluetoothDataType` is the supported public way to ask it.
/// The call costs ~60-120ms of CPU, so we run it off the main thread on a slow timer.
enum BatteryReader {

    enum ReadError: Error {
        case launchFailed(String)
        case badOutput
    }

    static func read() throws -> [PodsDevice] {
        let data = try runSystemProfiler()
        return try parse(data)
    }

    // MARK: - Process

    private static func runSystemProfiler() throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json"]

        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw ReadError.launchFailed(error.localizedDescription)
        }

        // Read before waiting so a large payload can't deadlock on a full pipe buffer.
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard !data.isEmpty else { throw ReadError.badOutput }
        return data
    }

    // MARK: - Parsing

    /// The JSON is `{ SPBluetoothDataType: [ { device_connected: [ { "Name": {...} } ] } ] }`
    /// — each device is a single-key dictionary keyed by its display name.
    static func parse(_ data: Data) throws -> [PodsDevice] {
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let sections = root["SPBluetoothDataType"] as? [[String: Any]]
        else { throw ReadError.badOutput }

        var devices: [PodsDevice] = []

        for section in sections {
            guard let connected = section["device_connected"] as? [[String: Any]] else { continue }

            for entry in connected {
                for (name, raw) in entry {
                    guard let fields = raw as? [String: Any] else { continue }

                    let device = PodsDevice(
                        name: name,
                        address: fields["device_address"] as? String ?? name,
                        left: percent(fields["device_batteryLevelLeft"]),
                        right: percent(fields["device_batteryLevelRight"]),
                        caseLevel: percent(fields["device_batteryLevelCase"]),
                        single: percent(fields["device_batteryLevelMain"])
                            ?? percent(fields["device_batteryLevel"])
                    )

                    // A phone or keyboard has no battery keys here; only keep things we can show.
                    if device.hasAnyReading { devices.append(device) }
                }
            }
        }

        // Stable order so the menu bar doesn't flip between two connected sets of buds.
        return devices.sorted { $0.address < $1.address }
    }

    /// Values arrive as `"56\u{00a0}%"` — a non-breaking space before the sign.
    private static func percent(_ value: Any?) -> Int? {
        guard let string = value as? String else { return nil }
        let digits = string.filter(\.isNumber)
        guard let number = Int(digits), (0...100).contains(number) else { return nil }
        return number
    }
}
