import ArgumentParser
import Foundation
import RupaResponsivenessBaseline

@main
struct ResponsivenessBaselineCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rupa-responsiveness-baseline",
        abstract: """
            Records the responsiveness baseline of the plan preparation path \
            against the RupaRendering performance acceptance table. No drawing \
            is measured, because the viewport draws through a mounted RealityKit \
            frame this process cannot bring up, so the drawing row reports no \
            duration and the best exit code a clean run produces is 3.
            """
    )

    @Option(name: .long, help: "Number of bodies in the fixture.")
    var bodies: Int?

    @Option(name: .long, help: "Lateral segment count per body.")
    var segments: Int?

    @Option(name: .long, help: "Discarded warm-up iterations.")
    var warmups: Int = 1

    @Option(name: .long, help: "Measured iterations.")
    var iterations: Int = 10

    @Option(
        name: .long,
        help: """
            Frame interval in milliseconds. Omit to use the derived value and \
            record the derivation rule in the report.
            """
    )
    var frameIntervalMilliseconds: Double?

    @Option(
        name: .long,
        help: """
            Minimum supported device memory in bytes. Omit to use the derived \
            value and record the derivation rule in the report.
            """
    )
    var minimumMemoryBytes: UInt64?

    @Option(
        name: .customLong("rupakit-path"),
        help: "Path to the RupaKit repository whose revision is recorded."
    )
    var rupaKitPath: String = FileManager.default.currentDirectoryPath

    @Option(
        name: .customLong("swift-cad-path"),
        help: "Path to the swift-CAD repository whose revision is recorded."
    )
    var swiftCADPath: String?

    @Flag(name: .long, help: "Emit the report as JSON instead of a table.")
    var json = false

    @Option(name: .long, help: "Write the JSON report to this path.")
    var output: String?

    func run() async throws {
        var parameters = ResponsivenessFixture.Parameters.standard
        if let bodies {
            parameters.bodyCount = bodies
        }
        if let segments {
            parameters.segmentCount = segments
        }
        let environment = try ResponsivenessEnvironment(
            frameIntervalSeconds: frameIntervalMilliseconds.map { $0 / 1000.0 },
            minimumMemoryBytes: minimumMemoryBytes
        )
        let resolvedSwiftCADPath = swiftCADPath
            ?? URL(fileURLWithPath: rupaKitPath)
                .deletingLastPathComponent()
                .appendingPathComponent("swift-CAD")
                .path
        let configuration = ResponsivenessBaselineRunner.Configuration(
            fixture: parameters,
            warmupCount: warmups,
            iterationCount: iterations,
            environment: environment,
            rupaKitRevision: try Self.gitRevision(at: rupaKitPath),
            swiftCADRevision: try Self.gitRevision(at: resolvedSwiftCADPath)
        )
        let report = try await Self.measure(configuration: configuration)

        if let output {
            let data = try Self.encode(report)
            try data.write(to: URL(fileURLWithPath: output))
        }
        if json {
            let data = try Self.encode(report)
            guard let text = String(data: data, encoding: .utf8) else {
                throw ResponsivenessBaselineError(
                    code: .invalidMeasurementRequest,
                    message: "The report could not be encoded as UTF-8 text."
                )
            }
            print(text)
        } else {
            print(Self.render(report))
        }
        if report.rows.contains(where: { $0.verdict == .rejects }) {
            throw ExitCode(Self.rejectingExitCode)
        }
        if report.rows.contains(where: { $0.verdict == .notMeasured }) {
            throw ExitCode(Self.incompleteExitCode)
        }
    }

    /// At least one acceptance row rejected. Distinct from the failure exit code
    /// so a script can tell a measured rejection from a measurement that never
    /// produced a report.
    private static let rejectingExitCode: Int32 = 2

    /// No row rejected, but at least one was not measured, so the baseline is
    /// incomplete and must not be read as passing.
    private static let incompleteExitCode: Int32 = 3

    /// Reads a repository revision. A revision that cannot be read is a typed
    /// failure, because a report without both revisions cannot be compared to
    /// another report.
    ///
    /// A working tree carrying uncommitted changes under `path` records the
    /// revision with a `-dirty` suffix, because the measured sources are then
    /// not the ones the revision names. The status is scoped to `path` rather
    /// than the whole repository, so unrelated changes elsewhere in a repository
    /// that also holds other packages do not mark the revision.
    private static func gitRevision(at path: String) throws -> String {
        let revision = try runGit(["-C", path, "rev-parse", "HEAD"], at: path)
        guard revision.isEmpty == false else {
            throw ResponsivenessBaselineError(
                code: .invalidMeasurementRequest,
                message: "The revision read at \(path) was empty."
            )
        }
        let status = try runGit(["-C", path, "status", "--porcelain", "--", path], at: path)
        return status.isEmpty ? revision : revision + "-dirty"
    }

    /// Runs one git invocation and returns its trimmed standard output. A git
    /// process that cannot start, or that exits non-zero, is a typed failure.
    private static func runGit(_ arguments: [String], at path: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            throw ResponsivenessBaselineError(
                code: .invalidMeasurementRequest,
                message: "git could not be started to read the revision at \(path): \(error)."
            )
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ResponsivenessBaselineError(
                code: .invalidMeasurementRequest,
                message: """
                    git \(arguments.joined(separator: " ")) failed at \(path) with \
                    status \(process.terminationStatus).
                    """
            )
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw ResponsivenessBaselineError(
                code: .invalidMeasurementRequest,
                message: "git output at \(path) was not UTF-8 text."
            )
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @MainActor
    private static func measure(
        configuration: ResponsivenessBaselineRunner.Configuration
    ) async throws -> ResponsivenessBaselineReport {
        let runner = try ResponsivenessBaselineRunner(configuration: configuration)
        return try await runner.run()
    }

    private static func encode(_ report: ResponsivenessBaselineReport) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(report)
    }

    private static func render(_ report: ResponsivenessBaselineReport) -> String {
        var lines: [String] = []
        lines.append("Fixture      \(report.fixture.name) v\(report.fixture.version)")
        lines.append("Digest       \(report.contentDigest)")
        lines.append(
            "Content      \(report.sceneItemCount) items, \(report.vertexCount) vertices, "
                + "\(report.faceCount) faces, \(report.planTriangleCount) plan triangles"
        )
        lines.append(
            "Context      \(report.context.buildConfiguration), \(report.context.hostModel), "
                + "\(report.context.operatingSystemVersion)"
        )
        lines.append(
            "Revisions    RupaKit \(report.context.rupaKitRevision), "
                + "swift-CAD \(report.context.swiftCADRevision)"
        )
        lines.append(
            "Environment  frameInterval "
                + String(format: "%.3f ms", report.environment.frameIntervalSeconds * 1000.0)
                + (report.environment.frameIntervalIsDerived ? " (derived)" : " (supplied)")
                + ", minimumMemory "
                + String(
                    format: "%.2f GB",
                    Double(report.environment.minimumMemoryBytes) / (1024.0 * 1024.0 * 1024.0)
                )
                + (report.environment.minimumMemoryIsDerived ? " (derived)" : " (supplied)")
        )
        lines.append("")
        lines.append("Row                          Verdict       Measured         Threshold")
        lines.append(String(repeating: "-", count: 78))
        for row in report.rows {
            let title = row.row.title.padding(toLength: 28, withPad: " ", startingAt: 0)
            let verdict = row.verdict.rawValue.padding(toLength: 13, withPad: " ", startingAt: 0)
            let measured = row.measured.padding(toLength: 16, withPad: " ", startingAt: 0)
            lines.append("\(title) \(verdict) \(measured) \(row.threshold)")
        }
        lines.append("")
        for row in report.rows {
            lines.append("\(row.row.title): \(row.detail)")
        }
        lines.append("")
        lines.append("Derivation rule: \(report.environmentDerivationRule)")
        return lines.joined(separator: "\n")
    }
}
