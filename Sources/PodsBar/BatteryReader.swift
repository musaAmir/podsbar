import CoreFoundation
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

    var hasAnyReading: Bool {
        left != nil || right != nil || caseLevel != nil || single != nil
    }

    var isSingleCell: Bool { left == nil && right == nil && single != nil }
}

/// Reads AirPods battery levels from `system_profiler`.
///
/// Uses the Bluetooth report rather than relying on private IOKit battery keys.
enum BatteryReader {

    enum ReadError: LocalizedError {
        case badOutput

        var errorDescription: String? { "macOS returned an unreadable Bluetooth report." }
    }

    static func read() async throws -> [PodsDevice] {
        // Parse away from the main actor as well as launching the process off-thread.
        let task = Task.detached(priority: .utility) {
            let data = try await ProcessOutput.run(
                executable: URL(fileURLWithPath: "/usr/sbin/system_profiler"),
                arguments: ["SPBluetoothDataType", "-json", "-timeout", "10"]
            )
            try Task.checkCancellation()
            return try parse(data)
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    // MARK: - Parsing

    /// The JSON is `{ SPBluetoothDataType: [ { device_connected: [ { "Name": {...} } ] } ] }`
    /// — each device is a single-key dictionary keyed by its display name.
    static func parse(_ data: Data) throws -> [PodsDevice] {
        guard
            let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let sections = root["SPBluetoothDataType"] as? [[String: Any]]
        else { throw ReadError.badOutput }

        var devices: [String: PodsDevice] = [:]

        for section in sections {
            guard let connected = section["device_connected"] as? [[String: Any]] else { continue }

            for entry in connected {
                for (name, raw) in entry {
                    guard let fields = raw as? [String: Any] else { continue }
                    // Input devices can expose the same single-battery key as headphones.
                    if let type = fields["device_minorType"] as? String {
                        let type = type.lowercased()
                        if ["keyboard", "mouse", "trackpad", "pointing"].contains(where: type.contains) { continue }
                    }

                    let device = PodsDevice(
                        name: name,
                        address: (fields["device_address"] as? String)
                            .map(normalizeAddress) ?? name,
                        left: percent(fields["device_batteryLevelLeft"]),
                        right: percent(fields["device_batteryLevelRight"]),
                        caseLevel: percent(fields["device_batteryLevelCase"]),
                        single: percent(fields["device_batteryLevelMain"])
                            ?? percent(fields["device_batteryLevel"])
                    )

                    // Keep connected devices only when the report provides a battery reading.
                    if device.hasAnyReading {
                        // Reports may repeat a device across controller sections.
                        // Preserve readings from both entries instead of duplicating rows.
                        if let previous = devices[device.address] {
                            devices[device.address] = PodsDevice(
                                name: name, address: device.address,
                                left: device.left ?? previous.left,
                                right: device.right ?? previous.right,
                                caseLevel: device.caseLevel ?? previous.caseLevel,
                                single: device.single ?? previous.single
                            )
                        } else {
                            devices[device.address] = device
                        }
                    }
                }
            }
        }

        // Stable order so the menu bar doesn't flip between two connected sets of buds.
        return devices.values.sorted { $0.address < $1.address }
    }

    static func normalizeAddress(_ address: String) -> String {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        // A name is the fallback identifier if macOS omits the hardware address.
        guard trimmed.contains(":") || trimmed.contains("-"),
              trimmed.utf8.allSatisfy({ byte in
                  (48...57).contains(byte) || (65...70).contains(byte)
                      || (97...102).contains(byte) || byte == 58 || byte == 45
              }) else { return trimmed }
        return trimmed.replacingOccurrences(of: ":", with: "-").uppercased()
    }

    /// Values arrive as `"56\u{00a0}%"` — a non-breaking space before the sign.
    private static func percent(_ value: Any?) -> Int? {
        if let string = value as? String {
            var text = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.hasSuffix("%") { text.removeLast() }
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, text.utf8.allSatisfy({ (48...57).contains($0) }),
                  let number = Int(text), (0...100).contains(number) else { return nil }
            return number
        }
        if let number = value as? NSNumber,
           CFGetTypeID(number) != CFBooleanGetTypeID(),
           (0...100).contains(number.doubleValue),
           number.doubleValue.rounded() == number.doubleValue {
            return number.intValue
        }
        return nil
    }
}
