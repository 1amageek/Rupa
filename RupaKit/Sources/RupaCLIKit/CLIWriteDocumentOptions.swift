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

    public func target(sessionID: UUID?) -> CLIDocumentTarget {
        CLIDocumentTarget(
            fileURL: file.map(URL.init(fileURLWithPath:)),
            sessionID: sessionID
        )
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
