import ArgumentParser
import Foundation
import RupaCore

public struct CLIWriteDocumentOptions: ParsableArguments {
    @Argument(help: "Path to the .rupa project.")
    public var file: String?

    @Option(help: "Open document session UUID.")
    public var sessionID: String?

    @Option(help: "Expected document generation.")
    public var expectedGeneration: UInt64?

    @Option(help: "Expected workspace revision for workspace mutations.")
    public var expectedWorkspaceRevision: UInt64?

    @Flag(help: "Print a JSON result.")
    public var json: Bool = false

    public init() {}

    public func resolvedSessionID() throws -> UUID? {
        try CLISelectionInputParser.optionalSessionID(sessionID)
    }

    public func target(sessionID: UUID?) -> CLIDocumentTarget {
        return CLIDocumentTarget(
            fileURL: file.map(URL.init(fileURLWithPath:)),
            sessionID: sessionID
        )
    }

    public func generation() -> DocumentGeneration? {
        expectedGeneration.map(DocumentGeneration.init)
    }

    public func workspaceRevision() -> WorkspaceRevision? {
        expectedWorkspaceRevision.map(WorkspaceRevision.init)
    }
}
