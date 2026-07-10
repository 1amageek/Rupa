import Darwin
import Foundation
import Testing
import RupaCore

struct CLIProcessResult {
    var terminationStatus: Int32
    var standardOutputData: Data
    var standardErrorData: Data

    var standardOutput: String {
        String(decoding: standardOutputData, as: UTF8.self)
    }

    var standardError: String {
        String(decoding: standardErrorData, as: UTF8.self)
    }
}

actor CLIProcessGate {
    static let shared = CLIProcessGate(
        limit: min(8, max(2, ProcessInfo.processInfo.activeProcessorCount))
    )

    private let limit: Int
    private var availableSlotCount: Int
    private var waiters: [Waiter] = []
    private var cancelledWaiterIDs: Set<UUID> = []

    private struct Waiter {
        var id: UUID
        var continuation: CheckedContinuation<Bool, Never>
    }

    init(limit: Int) {
        let normalizedLimit = max(1, limit)
        self.limit = normalizedLimit
        self.availableSlotCount = normalizedLimit
    }

    func acquire() async throws {
        let waiterID = UUID()
        let acquired = await withTaskCancellationHandler {
            await acquireSlot(waiterID: waiterID)
        } onCancel: {
            Task {
                await self.cancelWaiter(id: waiterID)
            }
        }
        guard acquired else {
            throw CancellationError()
        }
        guard !Task.isCancelled else {
            release()
            throw CancellationError()
        }
    }

    func release() {
        while !waiters.isEmpty {
            let waiter = waiters.removeFirst()
            guard cancelledWaiterIDs.remove(waiter.id) == nil else {
                waiter.continuation.resume(returning: false)
                continue
            }
            waiter.continuation.resume(returning: true)
            return
        }

        cancelledWaiterIDs.removeAll(keepingCapacity: true)
        availableSlotCount = min(limit, availableSlotCount + 1)
    }

    private func acquireSlot(waiterID: UUID) async -> Bool {
        guard !Task.isCancelled else {
            return false
        }
        guard cancelledWaiterIDs.remove(waiterID) == nil else {
            return false
        }
        guard availableSlotCount == 0 else {
            availableSlotCount -= 1
            return true
        }

        return await withCheckedContinuation { continuation in
            waiters.append(
                Waiter(
                    id: waiterID,
                    continuation: continuation
                )
            )
        }
    }

    private func cancelWaiter(id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else {
            cancelledWaiterIDs.insert(id)
            return
        }
        waiters.remove(at: index).continuation.resume(returning: false)
    }

    func snapshotForTesting() -> CLIProcessGateSnapshot {
        CLIProcessGateSnapshot(
            availableSlotCount: availableSlotCount,
            waiterCount: waiters.count,
            cancelledWaiterCount: cancelledWaiterIDs.count
        )
    }
}

struct CLIProcessGateSnapshot: Sendable, Equatable {
    var availableSlotCount: Int
    var waiterCount: Int
    var cancelledWaiterCount: Int
}

private enum CLIProcessGateContext {
    @TaskLocal static var ownsSlot = false
}

func withCLIProcessSequence<Result>(
    _ operation: () async throws -> Result
) async throws -> Result {
    try await CLIProcessGate.shared.acquire()
    do {
        let result = try await CLIProcessGateContext.$ownsSlot.withValue(true) {
            try await operation()
        }
        await CLIProcessGate.shared.release()
        return result
    } catch {
        await CLIProcessGate.shared.release()
        throw error
    }
}

func runCLI(
    _ arguments: [String],
    timeout: TimeInterval = 45
) async throws -> CLIProcessResult {
    guard !CLIProcessGateContext.ownsSlot else {
        try Task.checkCancellation()
        return try runCLIProcess(arguments, timeout: timeout)
    }

    try await CLIProcessGate.shared.acquire()
    do {
        try Task.checkCancellation()
        let result = try runCLIProcess(arguments, timeout: timeout)
        await CLIProcessGate.shared.release()
        return result
    } catch {
        await CLIProcessGate.shared.release()
        throw error
    }
}

private func runCLIProcess(
    _ arguments: [String],
    timeout: TimeInterval
) throws -> CLIProcessResult {
    let executableURL = try rupaExecutableURL()
    let capture = try makeProcessCapture()
    let outputHandle = try FileHandle(forWritingTo: capture.standardOutputURL)
    let errorHandle = try FileHandle(forWritingTo: capture.standardErrorURL)
    var outputClosed = false
    var errorClosed = false
    defer {
        if !outputClosed {
            recordCloseFailure(outputHandle, label: "stdout")
        }
        if !errorClosed {
            recordCloseFailure(errorHandle, label: "stderr")
        }
        removeProcessCaptureDirectory(capture.directory)
    }

    let process = Process()
    process.executableURL = executableURL
    process.arguments = arguments
    process.standardOutput = outputHandle
    process.standardError = errorHandle

    try process.run()
    try waitForProcessExit(
        process,
        executableURL: executableURL,
        arguments: arguments,
        timeout: timeout
    )

    try closeFileHandle(outputHandle, label: "stdout")
    outputClosed = true
    try closeFileHandle(errorHandle, label: "stderr")
    errorClosed = true

    return CLIProcessResult(
        terminationStatus: process.terminationStatus,
        standardOutputData: try Data(contentsOf: capture.standardOutputURL),
        standardErrorData: try Data(contentsOf: capture.standardErrorURL)
    )
}

private func waitForProcessExit(
    _ process: Process,
    executableURL: URL,
    arguments: [String],
    timeout: TimeInterval
) throws {
    guard timeout > 0 else {
        throw EditorError(
            code: .commandFailed,
            message: "CLI process timeout must be greater than zero."
        )
    }

    let deadline = Date().addingTimeInterval(timeout)
    while process.isRunning {
        if Date() >= deadline {
            terminateProcess(process)
            throw EditorError(
                code: .commandFailed,
                message: "CLI process timed out after \(timeout) seconds: \(([executableURL.path] + arguments).joined(separator: " "))"
            )
        }
        Thread.sleep(forTimeInterval: 0.02)
    }
}

private func terminateProcess(_ process: Process) {
    guard process.isRunning else {
        return
    }

    process.terminate()
    let terminateDeadline = Date().addingTimeInterval(1.0)
    while process.isRunning, Date() < terminateDeadline {
        Thread.sleep(forTimeInterval: 0.02)
    }
    guard process.isRunning else {
        return
    }

    kill(process.processIdentifier, SIGKILL)
    let killDeadline = Date().addingTimeInterval(1.0)
    while process.isRunning, Date() < killDeadline {
        Thread.sleep(forTimeInterval: 0.02)
    }
}

private struct CLIProcessCapture {
    var directory: URL
    var standardOutputURL: URL
    var standardErrorURL: URL
}

private func makeProcessCapture() throws -> CLIProcessCapture {
    let fileManager = FileManager.default
    let directory = fileManager.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try fileManager.createDirectory(
        at: directory,
        withIntermediateDirectories: true
    )

    let standardOutputURL = directory.appendingPathComponent("stdout.data")
    let standardErrorURL = directory.appendingPathComponent("stderr.data")
    try createEmptyCaptureFile(at: standardOutputURL, label: "stdout")
    try createEmptyCaptureFile(at: standardErrorURL, label: "stderr")

    return CLIProcessCapture(
        directory: directory,
        standardOutputURL: standardOutputURL,
        standardErrorURL: standardErrorURL
    )
}

private func createEmptyCaptureFile(at url: URL, label: String) throws {
    guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
        throw EditorError(
            code: .commandFailed,
            message: "Failed to create CLI \(label) capture file at \(url.path)."
        )
    }
}

private func closeFileHandle(_ handle: FileHandle, label: String) throws {
    do {
        try handle.close()
    } catch {
        throw EditorError(
            code: .commandFailed,
            message: "Failed to close CLI \(label) capture file: \(error)"
        )
    }
}

private func recordCloseFailure(_ handle: FileHandle, label: String) {
    do {
        try handle.close()
    } catch {
        Issue.record("Failed to close CLI \(label) capture file: \(error)")
    }
}

private func removeProcessCaptureDirectory(_ url: URL) {
    do {
        try FileManager.default.removeItem(at: url)
    } catch {
        Issue.record("Failed to remove CLI process capture directory: \(error)")
    }
}

private func rupaExecutableURL() throws -> URL {
    let fileManager = FileManager.default
    var candidates: [URL] = []
    let environment = ProcessInfo.processInfo.environment
    for key in ["BUILT_PRODUCTS_DIR", "TARGET_BUILD_DIR"] {
        guard let buildProductsDirectory = environment[key] else {
            continue
        }
        candidates.append(
            URL(fileURLWithPath: buildProductsDirectory)
                .appendingPathComponent("rupa")
        )
    }
    if let buildProductPaths = environment["__XCODE_BUILT_PRODUCTS_DIR_PATHS"] {
        for path in buildProductPaths.split(separator: ":") {
            candidates.append(
                URL(fileURLWithPath: String(path))
                    .appendingPathComponent("rupa")
            )
        }
    }
    candidates.append(
        Bundle.main.bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("rupa")
    )
    if let mainExecutableURL = Bundle.main.executableURL {
        let macOSDirectory = mainExecutableURL.deletingLastPathComponent()
        let contentsDirectory = macOSDirectory.deletingLastPathComponent()
        let bundleDirectory = contentsDirectory.deletingLastPathComponent()
        candidates.append(
            bundleDirectory
                .deletingLastPathComponent()
                .appendingPathComponent("rupa")
        )
    }
    if let testExecutablePath = CommandLine.arguments.first {
        let testExecutableURL = URL(fileURLWithPath: testExecutablePath)
        let macOSDirectory = testExecutableURL.deletingLastPathComponent()
        let contentsDirectory = macOSDirectory.deletingLastPathComponent()
        let testBundleDirectory = contentsDirectory.deletingLastPathComponent()
        let productsDirectory = testBundleDirectory.deletingLastPathComponent()
        candidates.append(productsDirectory.appendingPathComponent("rupa"))
    }
    for candidate in candidates {
        if fileManager.isExecutableFile(atPath: candidate.path) {
            return candidate
        }
    }

    throw EditorError(
        code: .commandFailed,
        message: "Could not locate the rupa executable in test build products. Checked: \(candidates.map(\.path).joined(separator: ", "))"
    )
}
