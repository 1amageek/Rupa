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

    @Option(parsing: .unconditional, help: "Offset distance numeric literal.")
    public var distance: Double

    @Option(help: "Length unit for the offset distance. Defaults to the workspace display unit.")
    public var unit: String?

    @Flag(name: .customLong("combine"), help: "Combine generated region output when supported.")
    public var combinesRegions: Bool = false

    public init() {}

    public func run() throws {
        try CLIAutomationCommandRunner.run(document: document) { sessionID in
            let lengthUnit = try CLIAutomationCommandRunner.lengthUnit(
                unitName: unit,
                document: document,
                sessionID: sessionID
            )
            return .offsetRegions(
                targets: try selection.decodedTargets(),
                distance: try CLIAutomationCommandRunner.lengthExpression(
                    value: distance,
                    unit: lengthUnit,
                    valueName: "Region offset distance"
                ),
                options: try options.options(),
                combinesRegions: combinesRegions
            )
        }
    }
}
