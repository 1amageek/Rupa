import ArgumentParser
import RupaAutomation
import RupaCore

public struct ModelEdgeFilletCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "edge-fillet",
        abstract: "Fillet editable body edges from SelectionTarget values."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @OptionGroup
    public var selection: CLISelectionTargetsOptions

    @Option(help: "Fillet radius numeric literal.")
    public var radius: Double

    @Option(help: "Length unit for the fillet radius.")
    public var unit: String = LengthDisplayUnit.millimeter.rawValue

    @Option(help: "Profile arc segment count.")
    public var segmentCount: Int = 8

    public init() {}

    public func run() throws {
        try CLIAutomationCommandRunner.run(
            document: document,
            command: .filletBodyEdges(
                targets: selection.decodedTargets(),
                radius: try CLIAutomationCommandRunner.lengthExpression(
                    value: radius,
                    unitName: unit,
                    valueName: "Edge fillet radius"
                ),
                segmentCount: segmentCount
            )
        )
    }
}
