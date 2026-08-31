import ArgumentParser
import RupaCore

public struct DimensionRemoveSelectionCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "remove-selection",
        abstract: "Remove one persistent selection dimension by SelectionDimensionID."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @Option(help: "Selection dimension UUID.")
    public var dimensionID: String

    public init() {}

    public func run() async throws {
        let id = try CLISelectionDimensionReferenceParser.dimensionID(
            dimensionID,
            valueName: "Selection dimension ID"
        )

        try await CLIAutomationCommandRunner.run(
            document: document,
            command: .removeSelectionDimension(id: id)
        )
    }
}
