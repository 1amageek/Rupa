import ArgumentParser
import RupaAutomation
import RupaCore

public struct ModelFaceOffsetCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "face-offset",
        abstract: "Offset an editable body face from a SelectionTarget."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @OptionGroup
    public var selection: CLISelectionTargetOptions

    @Option(help: "Offset distance numeric literal.")
    public var distance: Double

    @Option(help: "Length unit for the offset distance.")
    public var unit: String = LengthDisplayUnit.millimeter.rawValue

    public init() {}

    public func run() throws {
        try CLIAutomationCommandRunner.run(
            document: document,
            command: .offsetBodyFace(
                target: selection.decodedTarget(),
                distance: try CLIAutomationCommandRunner.lengthExpression(
                    value: distance,
                    unitName: unit,
                    valueName: "Face offset distance"
                )
            )
        )
    }
}
