import Darwin
import Foundation

struct CADBenchmarkCLIProcessResult: Sendable {
    let terminationStatus: Int32
    let standardOutputData: Data
    let standardErrorData: Data

    var standardOutput: String {
        String(decoding: standardOutputData, as: UTF8.self)
    }

    var standardError: String {
        String(decoding: standardErrorData, as: UTF8.self)
    }
}

func runCADBenchmarkCLI(
    _ arguments: [String],
    standardInput: Data? = nil,
    timeout: TimeInterval = 120
) throws -> CADBenchmarkCLIProcessResult {
    let process = Process()
    process.executableURL = try cadBenchmarkCLIExecutableURL()
    process.arguments = arguments

    let input = Pipe()
    let output = Pipe()
    let error = Pipe()
    process.standardInput = input
    process.standardOutput = output
    process.standardError = error

    try process.run()
    if let standardInput {
        try input.fileHandleForWriting.write(contentsOf: standardInput)
    }
    try input.fileHandleForWriting.close()

    let deadline = Date().addingTimeInterval(timeout)
    while process.isRunning {
        guard Date() < deadline else {
            process.terminate()
            let terminateDeadline = Date().addingTimeInterval(1)
            while process.isRunning, Date() < terminateDeadline {
                Thread.sleep(forTimeInterval: 0.01)
            }
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
            throw NSError(
                domain: "CADBenchmarkCLIProcessTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "CLI process timed out."]
            )
        }
        Thread.sleep(forTimeInterval: 0.01)
    }

    return CADBenchmarkCLIProcessResult(
        terminationStatus: process.terminationStatus,
        standardOutputData: output.fileHandleForReading.readDataToEndOfFile(),
        standardErrorData: error.fileHandleForReading.readDataToEndOfFile()
    )
}

private func cadBenchmarkCLIExecutableURL() throws -> URL {
    let executableName = "rupa-agent-cad-benchmark"
    let fileManager = FileManager.default
    var candidates: [URL] = []
    let environment = ProcessInfo.processInfo.environment

    for key in ["BUILT_PRODUCTS_DIR", "TARGET_BUILD_DIR"] {
        if let directory = environment[key] {
            candidates.append(URL(fileURLWithPath: directory).appendingPathComponent(executableName))
        }
    }
    if let paths = environment["__XCODE_BUILT_PRODUCTS_DIR_PATHS"] {
        candidates.append(contentsOf: paths.split(separator: ":").map {
            URL(fileURLWithPath: String($0)).appendingPathComponent(executableName)
        })
    }

    if let testExecutable = CommandLine.arguments.first {
        var directory = URL(fileURLWithPath: testExecutable).deletingLastPathComponent()
        for _ in 0..<6 {
            candidates.append(directory.appendingPathComponent(executableName))
            directory.deleteLastPathComponent()
        }
    }

    for bundle in Bundle.allBundles {
        candidates.append(
            bundle.bundleURL
                .deletingLastPathComponent()
                .appendingPathComponent(executableName)
        )
    }

    let packageBuildDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        .appendingPathComponent(".build")
    candidates.append(packageBuildDirectory.appendingPathComponent(executableName))
    candidates.append(
        packageBuildDirectory
            .appendingPathComponent("out")
            .appendingPathComponent("Products")
            .appendingPathComponent("Debug")
            .appendingPathComponent(executableName)
    )

    for candidate in candidates where fileManager.isExecutableFile(atPath: candidate.path) {
        return candidate
    }

    throw NSError(
        domain: "CADBenchmarkCLIProcessTests",
        code: 2,
        userInfo: [
            NSLocalizedDescriptionKey: "The benchmark CLI executable was not found.",
            "candidates": candidates.map(\.path).joined(separator: ", "),
        ]
    )
}
