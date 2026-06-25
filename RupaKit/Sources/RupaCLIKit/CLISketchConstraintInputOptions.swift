import ArgumentParser
import RupaCore

public struct CLISketchConstraintInputOptions: ParsableArguments {
    @Option(help: "SketchConstraint JSON object.")
    public var constraint: String?

    @Option(help: "JSON file containing one SketchConstraint object.")
    public var constraintFile: String?

    @OptionGroup
    public var typedConstraint: CLISketchConstraintTypedOptions

    public init() {}

    public func decodedConstraint() throws -> SketchConstraint {
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
