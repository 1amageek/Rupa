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
    static let shared = CLIProcessGate()

    func run(_ arguments: [String]) throws -> CLIProcessResult {
        try runCLIProcess(arguments)
    }
}

func runCLI(_ arguments: [String]) async throws -> CLIProcessResult {
    try await CLIProcessGate.shared.run(arguments)
}

private func runCLIProcess(_ arguments: [String]) throws -> CLIProcessResult {
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
    process.waitUntilExit()

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
    candidates.append(contentsOf: packageBuildProductCandidates())

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

private func packageBuildProductCandidates(
    sourceFilePath: String = #filePath
) -> [URL] {
    let sourceFileURL = URL(fileURLWithPath: sourceFilePath)
    let packageDirectory = sourceFileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let buildDirectory = packageDirectory.appendingPathComponent(".build", isDirectory: true)
    return [
        buildDirectory
            .appendingPathComponent("out", isDirectory: true)
            .appendingPathComponent("Products", isDirectory: true)
            .appendingPathComponent("Debug", isDirectory: true)
            .appendingPathComponent("rupa"),
        buildDirectory
            .appendingPathComponent("debug", isDirectory: true)
            .appendingPathComponent("rupa"),
        buildDirectory
            .appendingPathComponent("arm64-apple-macosx", isDirectory: true)
            .appendingPathComponent("debug", isDirectory: true)
            .appendingPathComponent("rupa"),
    ]
}
