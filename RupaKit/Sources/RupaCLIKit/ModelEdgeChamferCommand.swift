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

    @Option(help: "Chamfer distance numeric literal.")
    public var distance: Double

    @Option(help: "Length unit for the chamfer distance.")
    public var unit: String = LengthDisplayUnit.millimeter.rawValue

    public init() {}

    public func run() throws {
        try CLIAutomationCommandRunner.run(
            document: document,
            command: .chamferBodyEdges(
                targets: selection.decodedTargets(),
                distance: try CLIAutomationCommandRunner.lengthExpression(
                    value: distance,
                    unitName: unit,
                    valueName: "Edge chamfer distance"
                )
            )
        )
    }
}
