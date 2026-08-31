import ArgumentParser
import RupaAutomation
import RupaCore

public struct SketchConstraintAddCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "constraint-add",
        abstract: "Add one supported SketchConstraint to a sketch feature."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @Option(help: "Sketch feature ID.")
    public var featureID: String

    @OptionGroup
    public var constraintInput: CLISketchConstraintInputOptions

    public init() {}

    public func run() async throws {
        let parsedFeatureID = try CLIFeatureReferenceParser.featureID(
            featureID,
            valueName: "Sketch feature ID"
        )
        let parsedConstraint = try constraintInput.decodedConstraint()

        try await CLIAutomationCommandRunner.run(
            document: document,
            command: .addSketchConstraint(
                featureID: parsedFeatureID,
                constraint: parsedConstraint
            )
        )
    }
}
