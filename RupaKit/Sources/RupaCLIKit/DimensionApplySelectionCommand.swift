import ArgumentParser
import RupaCore

public struct DimensionApplySelectionCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "apply-selection",
        abstract: "Apply one persistent selection dimension target to supported source length, radius, or angle geometry by SelectionDimensionID."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @Option(help: "SelectionDimensionID UUID.")
    public var dimensionID: String

    public init() {}

    public func run() throws {
        let sessionID = try document.resolvedSessionID()
        let id = try CLISelectionDimensionReferenceParser.dimensionID(
            dimensionID,
            valueName: "SelectionDimensionID"
        )

        try CLIExitCode.run {
            let response = try CLIService().applySelectionDimensionTarget(
                target: document.target(sessionID: sessionID),
                id: id,
                mode: document.mode,
                expectedGeneration: document.generation(),
                dryRun: document.dryRun,
                forceFileEdit: document.forceFileEdit,
                client: document.agentClient(sessionID: sessionID)
            )
            try CLIOutput.write(response: response, asJSON: document.json)
        }
    }
}
