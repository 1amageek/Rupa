import ArgumentParser
import RupaAutomation
import RupaCore

public struct SketchSlotCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "slot",
        abstract: "Create a slot profile from a supported open source sketch curve or chain."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @OptionGroup
    public var selection: CLISelectionTargetOptions

    @Option(help: "Slot width numeric literal.")
    public var width: Double

    @Option(help: "Length unit for the slot width. Defaults to the document display unit.")
    public var unit: String?

    public init() {}

    public func run() throws {
        try CLIAutomationCommandRunner.run(document: document) { sessionID in
            let lengthUnit = try CLIAutomationCommandRunner.lengthUnit(
                unitName: unit,
                document: document,
                sessionID: sessionID
            )
            return .createSlotSketch(
                target: try selection.decodedTarget(),
                width: try CLIAutomationCommandRunner.lengthExpression(
                    value: width,
                    unit: lengthUnit,
                    valueName: "Slot width"
                )
            )
        }
    }
}
