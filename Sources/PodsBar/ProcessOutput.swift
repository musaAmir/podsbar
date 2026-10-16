import Darwin
import Foundation

/// A short-lived subprocess with bounded output, a deadline, and cancellation.
/// Dispatch sources drain the pipe without holding a worker thread while the tool runs.
enum ProcessOutput {
    enum Failure: LocalizedError, Equatable {
        case launchFailed(String)
        case timedOut
        case outputTooLarge
        case unsuccessfulExit(Int32)
        case readFailed

        var errorDescription: String? {
            switch self {
            case .launchFailed(let message): return "Couldn't start the Bluetooth scan: \(message)"
            case .timedOut: return "The Bluetooth scan timed out. Try refreshing again."
            case .outputTooLarge: return "The Bluetooth scan returned too much data."
            case .unsuccessfulExit(let status): return "The Bluetooth scan failed (exit \(status))."
            case .readFailed: return "Couldn't read the Bluetooth scan."
            }
        }
    }

    static func run(
        executable: URL, arguments: [String], timeout: TimeInterval = 15,
        outputLimit: Int = 1_048_576
    ) async throws -> Data {
        let runner = Runner(executable: executable, arguments: arguments,
                            timeout: timeout, outputLimit: outputLimit)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { runner.start($0) }
        } onCancel: {
            runner.cancel()
        }
    }

    // All mutable state is confined to queue, including cancellation before launch.
    private final class Runner: @unchecked Sendable {
        private let queue = DispatchQueue(label: "com.amirmusa.podsbar.scan", qos: .utility)
        private let process = Process()
        private let pipe = Pipe()
        private let timeout: TimeInterval
        private let outputLimit: Int
        private var continuation: CheckedContinuation<Data, Error>?
        private var source: DispatchSourceRead?
        private var deadline: DispatchSourceTimer?
        private var output = Data()
        private var cancelled = false
        private var reachedEOF = false
        private var exitStatus: Int32?

        init(executable: URL, arguments: [String], timeout: TimeInterval, outputLimit: Int) {
            process.executableURL = executable
            process.arguments = arguments
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            process.standardInput = FileHandle.nullDevice
            self.timeout = timeout
            self.outputLimit = outputLimit
        }

        func start(_ continuation: CheckedContinuation<Data, Error>) {
            queue.async { [self] in
                self.continuation = continuation
                guard !cancelled else { finish(.failure(CancellationError())); return }

                let descriptor = pipe.fileHandleForReading.fileDescriptor
                let flags = fcntl(descriptor, F_GETFL)
                guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) >= 0 else {
                    finish(.failure(Failure.readFailed))
                    return
                }

                process.terminationHandler = { [self] process in
                    queue.async { [self] in
                        exitStatus = process.terminationStatus
                        completeIfReady()
                    }
                }

                do {
                    try process.run()
                } catch {
                    finish(.failure(Failure.launchFailed(error.localizedDescription)))
                    return
                }
                // Only the child should hold the write end, so its exit produces EOF.
                try? pipe.fileHandleForWriting.close()

                let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
                source.setEventHandler { [self] in drain(descriptor) }
                let readHandle = pipe.fileHandleForReading
                // Dispatch must finish cancelling its fd monitoring before the fd is closed.
                source.setCancelHandler { try? readHandle.close() }
                self.source = source
                source.resume()

                let deadline = DispatchSource.makeTimerSource(queue: queue)
                deadline.schedule(deadline: .now() + timeout)
                deadline.setEventHandler { [self] in finish(.failure(Failure.timedOut)) }
                self.deadline = deadline
                deadline.resume()
            }
        }

        func cancel() {
            queue.async { [self] in
                cancelled = true
                if continuation != nil { finish(.failure(CancellationError())) }
            }
        }

        private func drain(_ descriptor: Int32) {
            guard continuation != nil else { return }
            var buffer = [UInt8](repeating: 0, count: 16_384)
            while true {
                let count = Darwin.read(descriptor, &buffer, buffer.count)
                if count > 0 {
                    guard count <= outputLimit - output.count else {
                        finish(.failure(Failure.outputTooLarge))
                        return
                    }
                    output.append(contentsOf: buffer.prefix(count))
                } else if count == 0 {
                    reachedEOF = true
                    source?.cancel()
                    completeIfReady()
                    return
                } else if errno == EINTR {
                    continue
                } else if errno == EAGAIN || errno == EWOULDBLOCK {
                    return
                } else {
                    finish(.failure(Failure.readFailed))
                    return
                }
            }
        }

        private func completeIfReady() {
            guard let status = exitStatus, reachedEOF else { return }
            finish(status == 0 ? .success(output) : .failure(Failure.unsuccessfulExit(status)))
        }

        private func finish(_ result: Result<Data, Error>) {
            guard let continuation else { return }
            self.continuation = nil
            // This is our own read-only scanner; don't leave it running after timeout/cancel.
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.terminationHandler = nil
            if let source {
                source.cancel()
                self.source = nil
            } else {
                // Launch failed (or was cancelled) before a read source was installed.
                try? pipe.fileHandleForReading.close()
            }
            deadline?.cancel()
            deadline = nil
            try? pipe.fileHandleForWriting.close()
            output = Data()
            continuation.resume(with: result)
        }
    }
}
