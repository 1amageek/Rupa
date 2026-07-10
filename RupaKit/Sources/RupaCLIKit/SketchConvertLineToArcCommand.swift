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

    @Option(parsing: .unconditional, help: "Sagitta numeric literal.")
    public var sagitta: Double

    @Option(help: "Length unit for the sagitta. Defaults to the workspace display unit.")
    public var unit: String?

    public init() {}

    public func run() throws {
        try CLIAutomationCommandRunner.run(document: document) { sessionID in
            let lengthUnit = try CLIAutomationCommandRunner.lengthUnit(
                unitName: unit,
                document: document,
                sessionID: sessionID
            )
            return .convertSketchLineToArc(
                target: try selection.decodedTarget(),
                sagitta: try CLIAutomationCommandRunner.lengthExpression(
                    value: sagitta,
                    unit: lengthUnit,
                    valueName: "Line-to-arc sagitta"
                )
            )
        }
    }
}
