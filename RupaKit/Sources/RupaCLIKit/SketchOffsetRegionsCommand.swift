import ArgumentParser
import RupaAutomation
import RupaCore

public struct SketchOffsetRegionsCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "offset-regions",
        abstract: "Offset one or more supported source profile region targets."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @OptionGroup
    public var selection: CLISelectionTargetsOptions

    @OptionGroup
    public var options: CLIOffsetCurveOptions

    @Option(help: "Offset distance numeric literal.")
    public var distance: Double

    @Option(help: "Length unit for the offset distance.")
    public var unit: String = LengthDisplayUnit.millimeter.rawValue

    @Flag(name: .customLong("combine"), help: "Combine generated region output when supported.")
    public var combinesRegions: Bool = false

    public init() {}

    public func run() throws {
        try CLIAutomationCommandRunner.run(
            document: document,
            command: .offsetRegions(
                targets: selection.decodedTargets(),
                distance: try CLIAutomationCommandRunner.lengthExpression(
                    value: distance,
                    unitName: unit,
                    valueName: "Region offset distance"
                ),
                options: try options.options(),
                combinesRegions: combinesRegions
            )
        )
    }
}
