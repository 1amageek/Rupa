import ArgumentParser
import RupaAutomation
import RupaCore

public struct SketchConstraintAddCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "constraint-add",
        abstract: "Add one supported SketchConstraint to a sketch feature."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @Option(help: "Sketch feature ID.")
    public var featureID: String

    @Option(help: "SketchConstraint JSON object.")
    public var constraint: String?

    @Option(help: "JSON file containing one SketchConstraint object.")
    public var constraintFile: String?

    public init() {}

    public func run() throws {
        let parsedFeatureID = try CLIFeatureReferenceParser.featureID(
            featureID,
            valueName: "Sketch feature ID"
        )
        let parsedConstraint: SketchConstraint = try CLISelectionInputParser.decodeSingleSelectionInput(
            inlinePayload: constraint,
            filePath: constraintFile,
            valueName: "SketchConstraint"
        )

        try CLIAutomationCommandRunner.run(
            document: document,
            command: .addSketchConstraint(
                featureID: parsedFeatureID,
                constraint: parsedConstraint
            )
        )
    }
}
