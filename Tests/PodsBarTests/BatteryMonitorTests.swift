import Foundation
import XCTest
@testable import PodsBar

@MainActor
final class BatteryMonitorTests: XCTestCase {
    @MainActor
    private final class Reader {
        var calls = 0
        var pending: [CheckedContinuation<[PodsDevice], Error>] = []

        func read() async throws -> [PodsDevice] {
            calls += 1
            return try await withCheckedThrowingContinuation { pending.append($0) }
        }

        func complete(_ devices: [PodsDevice] = []) { pending.removeFirst().resume(returning: devices) }
        func fail() { pending.removeFirst().resume(throwing: ProcessOutput.Failure.timedOut) }
    }

    private func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !condition() {
            guard ContinuousClock.now < deadline else {
                XCTFail("Condition did not become true", file: file, line: line)
                throw CancellationError()
            }
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    private func device(_ address: String) -> PodsDevice {
        PodsDevice(name: address, address: address, left: 50, right: 60)
    }

    private func isolatedDefaults() -> UserDefaults {
        let suite = "PodsBarTests.\(UUID().uuidString)"
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }
        return UserDefaults(suiteName: suite)!
    }

    func testRepeatedStartAndConcurrentRefreshUseOneScan() async throws {
        let reader = Reader()
        let monitor = BatteryMonitor(defaults: isolatedDefaults(), read: { try await reader.read() })
        defer { monitor.stop() }
        monitor.start()
        monitor.start()
        monitor.refresh()
        try await waitUntil { reader.calls == 1 }
        reader.complete([device("A")])
        try await waitUntil { !monitor.isRefreshing }
        monitor.start()
        monitor.refreshIfNeeded()
        XCTAssertEqual(reader.calls, 1)
        XCTAssertEqual(monitor.primary?.address, "A")
    }

    func testFailureKeepsReadingsAndLastSuccessfulTimestamp() async throws {
        let reader = Reader()
        let monitor = BatteryMonitor(defaults: isolatedDefaults(), read: { try await reader.read() })
        defer { monitor.stop() }
        monitor.refresh()
        try await waitUntil { reader.calls == 1 }
        reader.complete([device("A")])
        try await waitUntil { !monitor.isRefreshing }
        let updated = monitor.lastUpdated
        monitor.refresh()
        try await waitUntil { reader.calls == 2 }
        reader.fail()
        try await waitUntil { !monitor.isRefreshing }
        XCTAssertEqual(monitor.primary?.address, "A")
        XCTAssertEqual(monitor.lastUpdated, updated)
        XCTAssertNotNil(monitor.lastError)
        monitor.refreshIfNeeded()
        try await waitUntil { reader.calls == 3 }
        reader.complete()
        try await waitUntil { !monitor.isRefreshing }
        XCTAssertNil(monitor.lastError)
    }

    func testSleepCancelsAndLateResultCannotOverwriteNewScan() async throws {
        let reader = Reader()
        let monitor = BatteryMonitor(defaults: isolatedDefaults(), read: { try await reader.read() })
        defer { monitor.stop() }
        monitor.refresh()
        try await waitUntil { reader.calls == 1 }
        monitor.suspend()
        monitor.refresh()
        XCTAssertFalse(monitor.isRefreshing)
        XCTAssertEqual(reader.calls, 1)
        monitor.resume()
        try await waitUntil { reader.calls == 2 }
        // Simulate an old reader that ignores cancellation and returns after wake.
        reader.complete([device("stale")])
        reader.complete([device("current")])
        try await waitUntil { !monitor.isRefreshing }
        XCTAssertEqual(monitor.primary?.address, "current")
    }

    func testPreferredDevicePersistsAndFallsBackWhenDisconnected() async throws {
        let reader = Reader()
        let defaults = isolatedDefaults()
        defaults.set("aa:bb", forKey: "pinnedAddress")
        let monitor = BatteryMonitor(defaults: defaults, read: { try await reader.read() })
        defer { monitor.stop() }
        monitor.refresh()
        try await waitUntil { reader.calls == 1 }
        reader.complete([device("00-11"), device("AA-BB")])
        try await waitUntil { !monitor.isRefreshing }
        XCTAssertEqual(monitor.primary?.address, "AA-BB")
        monitor.refresh()
        try await waitUntil { reader.calls == 2 }
        reader.complete([device("00-11")])
        try await waitUntil { !monitor.isRefreshing }
        XCTAssertEqual(monitor.primary?.address, "00-11")
        XCTAssertEqual(monitor.pinnedAddress, "AA-BB")
        monitor.pinnedAddress = nil
        XCTAssertNil(defaults.string(forKey: "pinnedAddress"))
    }

    func testConnectionBurstCoalescesToOneFollowUp() async throws {
        let reader = Reader()
        let monitor = BatteryMonitor(defaults: isolatedDefaults(), read: { try await reader.read() },
                                     connectionDelay: .milliseconds(30))
        defer { monitor.stop() }
        monitor.refresh()
        try await waitUntil { reader.calls == 1 }
        reader.complete([device("A")])
        try await waitUntil { !monitor.isRefreshing }
        for _ in 0..<25 { monitor.refreshAfterConnectionChange() }
        try await waitUntil { reader.calls == 2 }
        reader.complete([device("A")])
        try await waitUntil { !monitor.isRefreshing }
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(reader.calls, 2)
    }

    func testFollowUpIsNotLostWhileScanIsRunning() async throws {
        let reader = Reader()
        let monitor = BatteryMonitor(defaults: isolatedDefaults(), read: { try await reader.read() },
                                     connectionDelay: .milliseconds(20))
        defer { monitor.stop() }
        monitor.refreshAfterConnectionChange()
        try await waitUntil { reader.calls == 1 }
        try await Task.sleep(for: .milliseconds(60))
        reader.complete()
        try await waitUntil { reader.calls == 2 }
        reader.complete([device("fresh")])
        try await waitUntil { !monitor.isRefreshing }
        XCTAssertEqual(monitor.primary?.address, "fresh")
    }

    func testSleepCancelsPendingConnectionRetry() async throws {
        let reader = Reader()
        let monitor = BatteryMonitor(defaults: isolatedDefaults(), read: { try await reader.read() },
                                     connectionDelay: .milliseconds(20))
        defer { monitor.stop() }
        monitor.refresh()
        try await waitUntil { reader.calls == 1 }
        reader.complete()
        try await waitUntil { !monitor.isRefreshing }
        monitor.refreshAfterConnectionChange()
        monitor.suspend()
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(reader.calls, 1)
    }

    func testAutomaticSelectionPrefersBudReadingsToCaseOnlyDevice() async throws {
        let reader = Reader()
        let monitor = BatteryMonitor(defaults: isolatedDefaults(), read: { try await reader.read() })
        defer { monitor.stop() }
        monitor.refresh()
        try await waitUntil { reader.calls == 1 }
        reader.complete([PodsDevice(name: "Case", address: "A", caseLevel: 80), device("B")])
        try await waitUntil { !monitor.isRefreshing }
        XCTAssertEqual(monitor.primary?.address, "B")
        monitor.pinnedAddress = "A"
        XCTAssertEqual(monitor.primary?.address, "A")
    }
}
