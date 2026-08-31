import ArgumentParser
import Foundation
import RupaCore

public struct CLIReadDocumentOptions: ParsableArguments {
    @Argument(help: "Path to the .rupa project.")
    public var file: String?

    @Option(help: "Access mode: live or file.")
    public var mode: CLIEditMode = .live

    @Option(help: "Open document session UUID for live mode.")
    public var sessionID: String?

    @Option(help: "Expected document generation for live mode.")
    public var expectedGeneration: UInt64?

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

}
