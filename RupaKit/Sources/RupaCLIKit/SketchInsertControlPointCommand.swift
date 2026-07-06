import ArgumentParser
import RupaAutomation

public struct SketchInsertControlPointCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "insert-control-point",
        abstract: "Insert a source spline control point at a scalar fraction."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @OptionGroup
    public var selection: CLISelectionTargetOptions

    @Option(parsing: .unconditional, help: "Scalar fraction along the selected spline.")
    public var fraction: Double

    public init() {}

    public func run() throws {
        try CLIAutomationCommandRunner.run(
            document: document,
            command: .insertSketchSplineControlPoint(
                target: selection.decodedTarget(),
                fraction: try CLIExpressionParser.scalar(
                    value: fraction,
                    valueName: "Control point insertion fraction"
                )
            )
        )
    }
}
