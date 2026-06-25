import ArgumentParser
import RupaAutomation
import RupaCore

public struct ModelVertexMoveCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "vertex-move",
        abstract: "Move an editable body vertex in the source profile plane."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @OptionGroup
    public var selection: CLISelectionTargetOptions

    @Option(help: "Delta X numeric literal in the source profile plane.")
    public var deltaX: Double = 0.0

    @Option(help: "Delta Y numeric literal in the source profile plane.")
    public var deltaY: Double = 0.0

    @Option(help: "Length unit for delta values.")
    public var unit: String = LengthDisplayUnit.millimeter.rawValue

    public init() {}

    public func run() throws {
        try CLIAutomationCommandRunner.run(
            document: document,
            command: .moveBodyVertex(
                target: selection.decodedTarget(),
                deltaX: try CLIAutomationCommandRunner.lengthExpression(
                    value: deltaX,
                    unitName: unit,
                    valueName: "Vertex move delta X"
                ),
                deltaY: try CLIAutomationCommandRunner.lengthExpression(
                    value: deltaY,
                    unitName: unit,
                    valueName: "Vertex move delta Y"
                )
            )
        )
    }
}
