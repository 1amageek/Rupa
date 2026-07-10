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

    @Option(parsing: .unconditional, help: "Delta X numeric literal in the source profile plane.")
    public var deltaX: Double = 0.0

    @Option(parsing: .unconditional, help: "Delta Y numeric literal in the source profile plane.")
    public var deltaY: Double = 0.0

    @Option(help: "Length unit for delta values. Defaults to the workspace display unit.")
    public var unit: String?

    public init() {}

    public func run() throws {
        try CLIAutomationCommandRunner.run(document: document) { sessionID in
            let lengthUnit = try CLIAutomationCommandRunner.lengthUnit(
                unitName: unit,
                document: document,
                sessionID: sessionID
            )
            return .moveBodyVertex(
                target: try selection.decodedTarget(),
                deltaX: try CLIAutomationCommandRunner.lengthExpression(
                    value: deltaX,
                    unit: lengthUnit,
                    valueName: "Vertex move delta X"
                ),
                deltaY: try CLIAutomationCommandRunner.lengthExpression(
                    value: deltaY,
                    unit: lengthUnit,
                    valueName: "Vertex move delta Y"
                )
            )
        }
    }
}
