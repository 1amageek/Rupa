import ArgumentParser
import RupaAutomation
import RupaCore

public struct SketchConstraintRemoveCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "constraint-remove",
        abstract: "Remove one existing SketchConstraint from a sketch feature."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @Option(help: "Sketch feature ID.")
    public var featureID: String

    @OptionGroup
    public var constraintInput: CLISketchConstraintInputOptions

    public init() {}

    public func run() throws {
        let parsedFeatureID = try CLIFeatureReferenceParser.featureID(
            featureID,
            valueName: "Sketch feature ID"
        )
        let parsedConstraint = try constraintInput.decodedConstraint()

        try CLIAutomationCommandRunner.run(
            document: document,
            command: .removeSketchConstraint(
                featureID: parsedFeatureID,
                constraint: parsedConstraint
            )
        )
    }
}
