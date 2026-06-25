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

    @OptionGroup
    public var typedConstraint: CLISketchConstraintTypedOptions

    public init() {}

    public func run() throws {
        let parsedFeatureID = try CLIFeatureReferenceParser.featureID(
            featureID,
            valueName: "Sketch feature ID"
        )
        let parsedConstraint = try parsedSketchConstraint()

        try CLIAutomationCommandRunner.run(
            document: document,
            command: .addSketchConstraint(
                featureID: parsedFeatureID,
                constraint: parsedConstraint
            )
        )
    }

    private func parsedSketchConstraint() throws -> SketchConstraint {
        let hasJSONInput = constraint != nil || constraintFile != nil
        if hasJSONInput {
            guard !typedConstraint.hasInput else {
                throw ValidationError("Provide either SketchConstraint JSON input or typed --kind options, not both.")
            }
            return try CLISelectionInputParser.decodeSingleSelectionInput(
                inlinePayload: constraint,
                filePath: constraintFile,
                valueName: "SketchConstraint"
            )
        }
        return try typedConstraint.decodedConstraint()
    }
}
