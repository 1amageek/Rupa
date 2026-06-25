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
    public var selection: CLISketchEditTargetOptions

    @Option(help: "Slot width numeric literal.")
    public var width: Double

    @Option(help: "Length unit for the slot width.")
    public var unit: String = LengthDisplayUnit.millimeter.rawValue

    public init() {}

    public func run() throws {
        try CLISketchEditCommandRunner.run(
            document: document,
            command: .createSlotSketch(
                target: selection.decodedTarget(),
                width: try CLISketchEditCommandRunner.lengthExpression(
                    value: width,
                    unitName: unit,
                    valueName: "Slot width"
                )
            )
        )
    }
}
