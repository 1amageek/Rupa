import ArgumentParser
import Foundation
import RupaCore

public struct CLIWriteDocumentOptions: ParsableArguments {
    @Argument(help: "Path to the .rupa project.")
    public var file: String?

    @Option(help: "Access mode: live or file.")
    public var mode: CLIEditMode = .live

    @Option(help: "Open document session UUID for live mode.")
    public var sessionID: String?

    @Option(help: "Expected document generation for live mode.")
    public var expectedGeneration: UInt64?

    @Option(help: "Expected workspace revision for live workspace mutations.")
    public var expectedWorkspaceRevision: UInt64?

    @Flag(help: "Validate the command without saving the changed file.")
    public var dryRun: Bool = false

    @OptionGroup
    public var destination: CLIWriteDestinationOptions

    @Flag(help: "Print a JSON result.")
    public var json: Bool = false

    public init() {}

    public func resolvedSessionID() throws -> UUID? {
        try CLISelectionInputParser.optionalSessionID(sessionID)
    }

    public func target(sessionID: UUID?) throws -> CLIDocumentTarget {
        try destination.validate(file: file, mode: mode, sessionID: sessionID)
        return CLIDocumentTarget(
            fileURL: file.map(URL.init(fileURLWithPath:)),
            sessionID: sessionID
        )
    }

    public func writePolicy(sessionID: UUID?) throws -> CLIDocumentWritePolicy {
        try destination.writePolicy(file: file, mode: mode, sessionID: sessionID)
    }

    public func generation() -> DocumentGeneration? {
        expectedGeneration.map(DocumentGeneration.init)
    }

    public func workspaceRevision() -> WorkspaceRevision? {
        expectedWorkspaceRevision.map(WorkspaceRevision.init)
    }

}

public struct CLIWriteDestinationOptions: ParsableArguments {
    @Flag(name: .customLong("in-place"), help: "Write file-mode mutations back to the input project. This is the default when --output is omitted.")
    public var inPlace: Bool = false

    @Option(help: "Write file-mode mutations to a new .rupa output project instead of modifying the input project.")
    public var output: String?

    public init() {}

    public func validate(
        file: String?,
        mode: CLIEditMode,
        sessionID: UUID?
    ) throws {
        try CLIDocumentWritePolicyResolver.validate(
            inPlace: inPlace,
            output: output,
            file: file,
            mode: mode,
            sessionID: sessionID
        )
    }

    public func writePolicy(
        file: String?,
        mode: CLIEditMode,
        sessionID: UUID?
    ) throws -> CLIDocumentWritePolicy {
        try CLIDocumentWritePolicyResolver.writePolicy(
            inPlace: inPlace,
            output: output,
            file: file,
            mode: mode,
            sessionID: sessionID
        )
    }

}

enum CLIDocumentWritePolicyResolver {
    static func writePolicy(
        inPlace: Bool,
        output: String?,
        file: String?,
        mode: CLIEditMode,
        sessionID: UUID?
    ) throws -> CLIDocumentWritePolicy {
        try validate(
            inPlace: inPlace,
            output: output,
            file: file,
            mode: mode,
            sessionID: sessionID
        )
        guard let output else {
            return .inPlace
        }
        let outputURL = URL(fileURLWithPath: output)
        guard outputURL.pathExtension.lowercased() == "rupa" else {
            throw ValidationError("--output must use the .rupa project extension.")
        }
        return .output(outputURL)
    }

    static func validate(
        inPlace: Bool,
        output: String?,
        file: String?,
        mode: CLIEditMode,
        sessionID: UUID?
    ) throws {
        guard !(inPlace && output != nil) else {
            throw ValidationError("--in-place and --output cannot be combined.")
        }
        guard !(output != nil && mode == .live) else {
            throw ValidationError("--output can only be used with --mode file.")
        }
        guard !(output != nil && sessionID != nil) else {
            throw ValidationError("--output cannot be combined with --session-id.")
        }
        guard !(inPlace && mode == .live) else {
            throw ValidationError("--in-place can only be used with --mode file.")
        }
        guard !(inPlace && sessionID != nil) else {
            throw ValidationError("--in-place cannot be combined with --session-id.")
        }
        guard !(output != nil && file == nil) else {
            throw ValidationError("--output requires an input document file path.")
        }
    }
}
