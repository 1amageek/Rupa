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

    @Option(parsing: .unconditional, help: "Fillet radius numeric literal.")
    public var radius: Double

    @Option(help: "Length unit for the fillet radius. Defaults to the workspace display unit.")
    public var unit: String?

    @Option(parsing: .unconditional, help: "Profile arc segment count.")
    public var segmentCount: Int = 8

    public init() {}

    public func run() throws {
        try CLIAutomationCommandRunner.run(document: document) { sessionID in
            let lengthUnit = try CLIAutomationCommandRunner.lengthUnit(
                unitName: unit,
                document: document,
                sessionID: sessionID
            )
            return .filletBodyEdges(
                targets: try selection.decodedTargets(),
                radius: try CLIAutomationCommandRunner.lengthExpression(
                    value: radius,
                    unit: lengthUnit,
                    valueName: "Edge fillet radius"
                ),
                segmentCount: segmentCount
            )
        }
    }
}
