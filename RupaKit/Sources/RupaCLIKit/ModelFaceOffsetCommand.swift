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

    @Option(parsing: .unconditional, help: "Offset distance numeric literal.")
    public var distance: Double

    @Option(help: "Length unit for the offset distance. Defaults to the document display unit.")
    public var unit: String?

    public init() {}

    public func run() throws {
        try CLIAutomationCommandRunner.run(document: document) { sessionID in
            let lengthUnit = try CLIAutomationCommandRunner.lengthUnit(
                unitName: unit,
                document: document,
                sessionID: sessionID
            )
            return .offsetBodyFace(
                target: try selection.decodedTarget(),
                distance: try CLIAutomationCommandRunner.lengthExpression(
                    value: distance,
                    unit: lengthUnit,
                    valueName: "Face offset distance"
                )
            )
        }
    }
}
