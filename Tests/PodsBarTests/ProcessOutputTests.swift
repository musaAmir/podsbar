import Darwin
import Foundation
import XCTest
@testable import PodsBar

final class ProcessOutputTests: XCTestCase {
    func testDrainsMoreThanAPipeBuffer() async throws {
        let output = try await ProcessOutput.run(
            executable: URL(fileURLWithPath: "/usr/bin/head"),
            arguments: ["-c", "262144", "/dev/zero"]
        )
        XCTAssertEqual(output, Data(repeating: 0, count: 262144))
    }

    func testDoesNotLoseOutputWhenProcessExitsImmediately() async throws {
        for _ in 0..<20 {
            let output = try await ProcessOutput.run(
                executable: URL(fileURLWithPath: "/usr/bin/printf"), arguments: ["battery data"]
            )
            XCTAssertEqual(String(decoding: output, as: UTF8.self), "battery data")
        }
    }

    func testNonzeroExitIsAnErrorEvenWithOutput() async throws {
        do {
            _ = try await ProcessOutput.run(executable: URL(fileURLWithPath: "/bin/sh"),
                                            arguments: ["-c", "printf partial; exit 7"])
            XCTFail("Accepted an unsuccessful scan")
        } catch {
            XCTAssertEqual(error as? ProcessOutput.Failure, .unsuccessfulExit(7))
        }
    }

    func testLaunchFailure() async throws {
        do {
            _ = try await ProcessOutput.run(executable: URL(fileURLWithPath: "/nonexistent/podsbar"), arguments: [])
            XCTFail("Launched a missing tool")
        } catch ProcessOutput.Failure.launchFailed { } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testDeadlineBoundsAHungScan() async throws {
        let start = ContinuousClock.now
        do {
            _ = try await ProcessOutput.run(executable: URL(fileURLWithPath: "/bin/sleep"),
                                            arguments: ["10"], timeout: 0.05)
            XCTFail("Scan did not time out")
        } catch {
            XCTAssertEqual(error as? ProcessOutput.Failure, .timedOut)
        }
        XCTAssertLessThan(start.duration(to: .now), .seconds(3))
    }

    func testOutputLimit() async throws {
        do {
            _ = try await ProcessOutput.run(executable: URL(fileURLWithPath: "/usr/bin/head"),
                                            arguments: ["-c", "262144", "/dev/zero"], outputLimit: 1024)
            XCTFail("Accepted oversized output")
        } catch {
            XCTAssertEqual(error as? ProcessOutput.Failure, .outputTooLarge)
        }
    }

    func testDeadlineStillAppliesWhenToolClosesOutputBeforeExiting() async throws {
        do {
            _ = try await ProcessOutput.run(executable: URL(fileURLWithPath: "/bin/sh"),
                                            arguments: ["-c", "exec 1>&-; exec /bin/sleep 10"], timeout: 0.05)
            XCTFail("Scan did not time out after closing stdout")
        } catch {
            XCTAssertEqual(error as? ProcessOutput.Failure, .timedOut)
        }
    }

    func testCancellationTerminatesTheOwnedChild() async throws {
        let pidFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let task = Task {
            try await ProcessOutput.run(executable: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "echo $$ > \"$1\"; exec /bin/sleep 10", "podsbar-test", pidFile.path])
        }
        defer {
            task.cancel()
            try? FileManager.default.removeItem(at: pidFile)
        }
        let deadline = ContinuousClock.now + .seconds(3)
        while !FileManager.default.fileExists(atPath: pidFile.path), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        let pid = try XCTUnwrap(Int32(String(contentsOf: pidFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)))
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancelled scan succeeded")
        } catch is CancellationError { } catch {
            XCTFail("Unexpected error: \(error)")
        }
        while kill(pid, 0) == 0, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(kill(pid, 0), -1, "Scanner was left running after cancellation")
        XCTAssertEqual(errno, ESRCH)
    }

    func testCancellationBeforeAndAfterLaunch() async throws {
        for delay in [Duration.zero, .milliseconds(30)] {
            let task = Task {
                try await ProcessOutput.run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["10"])
            }
            if delay > .zero { try await Task.sleep(for: delay) }
            let start = ContinuousClock.now
            task.cancel()
            do {
                _ = try await task.value
                XCTFail("Cancelled scan succeeded")
            } catch is CancellationError { } catch {
                XCTFail("Unexpected error: \(error)")
            }
            XCTAssertLessThan(start.duration(to: .now), .seconds(3))
        }
    }
}
