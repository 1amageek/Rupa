import ArgumentParser
import Foundation
import RupaAgentTransport
import RupaCore

public struct CLIWriteDocumentOptions: ParsableArguments {
    @Argument(help: "Path to the .swcad document for file or auto mode.")
    public var file: String?

    @Option(help: "Edit mode: auto, file, or live.")
    public var mode: CLIEditMode = .auto

    @Option(help: "Open document session UUID for live mode.")
    public var sessionID: String?

    @Option(help: "Expected document generation for live mode.")
    public var expectedGeneration: UInt64?

    @Flag(help: "Validate the command without saving the changed file.")
    public var dryRun: Bool = false

    @Flag(name: .customLong("in-place"), help: "Write file-mode mutations back to the input file. This is the default when --output is omitted.")
    public var inPlace: Bool = false

    @Option(help: "Write file-mode mutations to a new .swcad output file instead of modifying the input file.")
    public var output: String?

    @Flag(help: "Allow direct file mutation even if the app reports the same file as open.")
    public var forceFileEdit: Bool = false

    @Option(help: "Optional Rupa agent socket used to detect open document conflicts.")
    public var agentSocket: String?

    @Flag(help: "Print a JSON result.")
    public var json: Bool = false

    public init() {}

    public func resolvedSessionID() throws -> UUID? {
        try CLISelectionInputParser.optionalSessionID(sessionID)
    }

    public func target(sessionID: UUID?) throws -> CLIDocumentTarget {
        try validateWriteDestination(sessionID: sessionID)
        return CLIDocumentTarget(
            fileURL: file.map(URL.init(fileURLWithPath:)),
            sessionID: sessionID
        )
    }

    public func writePolicy(sessionID: UUID?) throws -> CLIDocumentWritePolicy {
        try validateWriteDestination(sessionID: sessionID)
        guard let output else {
            return .inPlace
        }
        let outputURL = URL(fileURLWithPath: output)
        guard outputURL.pathExtension.lowercased() == "swcad" else {
            throw ValidationError("--output must use the .swcad document extension.")
        }
        return .output(outputURL)
    }

    private func validateWriteDestination(sessionID: UUID?) throws {
        guard !(inPlace && output != nil) else {
            throw ValidationError("--in-place and --output cannot be combined.")
        }
        guard !(output != nil && mode == .live) else {
            throw ValidationError("--output can only be used in file or auto mode.")
        }
        guard !(output != nil && sessionID != nil) else {
            throw ValidationError("--output cannot be combined with --session-id.")
        }
        guard !(inPlace && mode == .live) else {
            throw ValidationError("--in-place can only be used in file or auto mode.")
        }
        guard !(inPlace && sessionID != nil) else {
            throw ValidationError("--in-place cannot be combined with --session-id.")
        }
        guard !(output != nil && file == nil) else {
            throw ValidationError("--output requires an input document file path.")
        }
    }

    public func generation() -> DocumentGeneration? {
        expectedGeneration.map(DocumentGeneration.init)
    }

    public func agentClient(sessionID: UUID?) -> AgentClient? {
        CLIAgentClientFactory.makeAgentClient(
            mode: mode,
            sessionID: sessionID,
            socket: agentSocket
        )
    }
}
