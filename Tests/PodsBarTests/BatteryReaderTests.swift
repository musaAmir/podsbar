import Foundation
import XCTest
@testable import PodsBar

final class BatteryReaderTests: XCTestCase {
    private func report(_ connected: [[String: Any]], disconnected: [[String: Any]] = []) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "SPBluetoothDataType": [["device_connected": connected, "device_not_connected": disconnected]]
        ])
    }

    func testConnectedReadingsAndStableOrder() throws {
        let data = try report([
            ["Renamed buds": ["device_address": "bb:22", "device_batteryLevelLeft": "56\u{00a0}%",
                              "device_batteryLevelRight": " 62 % ", "device_batteryLevelCase": "0%"]],
            ["Max": ["device_address": "AA-11", "device_batteryLevelMain": 100]],
            ["No readings": ["device_address": "CC-33"]]
        ], disconnected: [["Old buds": ["device_batteryLevelLeft": "99%"]]])
        let devices = try BatteryReader.parse(data)
        XCTAssertEqual(devices.map(\.address), ["AA-11", "BB-22"])
        XCTAssertTrue(devices[0].isSingleCell)
        XCTAssertEqual(devices[0].single, 100)
        XCTAssertEqual(devices[1].left, 56)
        XCTAssertEqual(devices[1].right, 62)
        XCTAssertEqual(devices[1].caseLevel, 0)
    }

    func testRejectsMalformedPercentagesInsteadOfExtractingDigits() throws {
        for value: Any in ["-5%", "101%", "1.5%", "5 of 10", "", true, 12.5, -1, 101] {
            let data = try report([["Buds": ["device_batteryLevelLeft": value]]])
            XCTAssertTrue(try BatteryReader.parse(data).isEmpty, "Accepted \(value)")
        }
    }

    func testSingleCellFallbackAndMissingCase() throws {
        let data = try report([["Beats": ["device_batteryLevel": "75%"]]])
        let device = try XCTUnwrap(BatteryReader.parse(data).first)
        XCTAssertEqual(device.address, "Beats")
        XCTAssertTrue(device.isSingleCell)
        XCTAssertNil(device.caseLevel)
        XCTAssertEqual(device.single, 75)
    }

    func testInputDevicesDoNotBecomeThePrimaryHeadphones() throws {
        let data = try report([
            ["Keyboard": ["device_minorType": "Keyboard", "device_batteryLevelMain": "99%"]],
            ["Mouse": ["device_minorType": "Mouse", "device_batteryLevelMain": "80%"]],
            ["Trackpad": ["device_minorType": "Trackpad", "device_batteryLevelMain": "70%"]],
            ["Renamed Max": ["device_minorType": "Headphones", "device_batteryLevelMain": "60%"]]
        ])
        XCTAssertEqual(try BatteryReader.parse(data).map(\.name), ["Renamed Max"])
    }

    func testAddressNormalizationPreservesFallbackNames() {
        XCTAssertEqual(BatteryReader.normalizeAddress(" aa:bb:cc:00:11:22 "), "AA-BB-CC-00-11-22")
        XCTAssertEqual(BatteryReader.normalizeAddress("My Beats"), "My Beats")
    }

    func testMergesDuplicateControllerEntries() throws {
        let data = try JSONSerialization.data(withJSONObject: ["SPBluetoothDataType": [
            ["device_connected": [["Buds": ["device_address": "aa:bb", "device_batteryLevelLeft": "30%"]]]],
            ["device_connected": [["Buds": ["device_address": "AA-BB", "device_batteryLevelRight": "40%"]]]]
        ]])
        let devices = try BatteryReader.parse(data)
        XCTAssertEqual(devices.count, 1)
        XCTAssertEqual(devices.first?.left, 30)
        XCTAssertEqual(devices.first?.right, 40)
    }

    func testEmptyAndInvalidReports() throws {
        XCTAssertTrue(try BatteryReader.parse(report([])).isEmpty)
        XCTAssertTrue(try BatteryReader.parse(Data(#"{"SPBluetoothDataType":[{}]}"#.utf8)).isEmpty)
        for json in ["", "not json", "{}", "[]", #"{"SPBluetoothDataType":{}}"#] {
            XCTAssertThrowsError(try BatteryReader.parse(Data(json.utf8)))
        }
    }
}
