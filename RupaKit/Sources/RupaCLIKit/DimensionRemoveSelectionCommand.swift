import ArgumentParser
import RupaCore

public struct DimensionRemoveSelectionCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "remove-selection",
        abstract: "Remove one persistent selection dimension by SelectionDimensionID."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @Option(help: "Selection dimension UUID.")
    public var dimensionID: String

    public init() {}

    public func run() throws {
        let sessionID = try document.resolvedSessionID()
        let id = try CLISelectionDimensionReferenceParser.dimensionID(
            dimensionID,
            valueName: "Selection dimension ID"
        )

        try CLIExitCode.run {
            let response = try CLIService().removeSelectionDimension(
                target: try document.target(sessionID: sessionID),
                id: id,
                mode: document.mode,
                expectedGeneration: document.generation(),
                dryRun: document.dryRun,
                writePolicy: try document.writePolicy(sessionID: sessionID),
                forceFileEdit: document.forceFileEdit,
                client: document.agentClient(sessionID: sessionID)
            )
            try CLIOutput.write(response: response, asJSON: document.json)
        }
    }
}
