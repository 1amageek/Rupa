import ArgumentParser
import RupaAutomation
import RupaCore

public struct SketchConvertLineToArcCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "convert-line-to-arc",
        abstract: "Convert a supported source sketch line into an arc."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @OptionGroup
    public var selection: CLISelectionTargetOptions

    @Option(help: "Sagitta numeric literal.")
    public var sagitta: Double

    @Option(help: "Length unit for the sagitta.")
    public var unit: String = LengthDisplayUnit.millimeter.rawValue

    public init() {}

    public func run() throws {
        try CLIAutomationCommandRunner.run(
            document: document,
            command: .convertSketchLineToArc(
                target: selection.decodedTarget(),
                sagitta: try CLIAutomationCommandRunner.lengthExpression(
                    value: sagitta,
                    unitName: unit,
                    valueName: "Line-to-arc sagitta"
                )
            )
        )
    }
}
