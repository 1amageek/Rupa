import ArgumentParser
import RupaCore

public struct DimensionApplySelectionCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "apply-selection",
        abstract: "Apply one persistent selection dimension target to supported source length, point-distance including arc endpoints and spline control points, radius, angle, or generated opposing face-pair geometry by SelectionDimensionID."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @Option(help: "SelectionDimensionID UUID.")
    public var dimensionID: String

    public init() {}

    public func run() async throws {
        let id = try CLISelectionDimensionReferenceParser.dimensionID(
            dimensionID,
            valueName: "SelectionDimensionID"
        )

        try await CLIAutomationCommandRunner.run(
            document: document,
            command: .applySelectionDimensionTarget(id: id)
        )
    }
}
