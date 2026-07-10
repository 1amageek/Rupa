import ArgumentParser
import RupaAutomation
import RupaCore

public struct ModelEdgeChamferCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "edge-chamfer",
        abstract: "Chamfer editable body edges from SelectionTarget values."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @OptionGroup
    public var selection: CLISelectionTargetsOptions

    @Option(parsing: .unconditional, help: "Chamfer distance numeric literal.")
    public var distance: Double

    @Option(help: "Length unit for the chamfer distance. Defaults to the workspace display unit.")
    public var unit: String?

    public init() {}

    public func run() throws {
        try CLIAutomationCommandRunner.run(document: document) { sessionID in
            let lengthUnit = try CLIAutomationCommandRunner.lengthUnit(
                unitName: unit,
                document: document,
                sessionID: sessionID
            )
            return .chamferBodyEdges(
                targets: try selection.decodedTargets(),
                distance: try CLIAutomationCommandRunner.lengthExpression(
                    value: distance,
                    unit: lengthUnit,
                    valueName: "Edge chamfer distance"
                )
            )
        }
    }
}
