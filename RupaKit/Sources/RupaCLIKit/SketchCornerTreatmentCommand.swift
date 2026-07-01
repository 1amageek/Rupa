import ArgumentParser
import RupaAutomation
import RupaCore

public struct SketchCornerTreatmentCommand: ParsableCommand {
    public enum Treatment: String, ExpressibleByArgument, Sendable {
        case fillet
        case chamfer

        var sketchCornerTreatment: SketchCornerTreatment {
            switch self {
            case .fillet:
                .fillet
            case .chamfer:
                .chamfer
            }
        }
    }

    public static let configuration = CommandConfiguration(
        commandName: "corner-treatment",
        abstract: "Apply a fillet or chamfer to a supported source sketch corner."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @OptionGroup
    public var selection: CLISelectionTargetOptions

    @Option(help: "Corner treatment: fillet or chamfer.")
    public var treatment: Treatment

    @Option(help: "Optional adjacent SelectionTarget JSON object.")
    public var adjacentTarget: String?

    @Option(help: "JSON file containing one optional adjacent SelectionTarget object.")
    public var adjacentTargetFile: String?

    @Option(help: "Fillet radius or chamfer distance numeric literal.")
    public var distance: Double

    @Option(help: "Length unit for the treatment distance. Defaults to the document display unit.")
    public var unit: String?

    public init() {}

    public func run() throws {
        try CLIAutomationCommandRunner.run(document: document) { sessionID in
            let lengthUnit = try CLIAutomationCommandRunner.lengthUnit(
                unitName: unit,
                document: document,
                sessionID: sessionID
            )
            return .applySketchCornerTreatment(
                target: try selection.decodedTarget(),
                adjacentTarget: try decodedAdjacentTarget(),
                distance: try CLIAutomationCommandRunner.lengthExpression(
                    value: distance,
                    unit: lengthUnit,
                    valueName: "Corner treatment distance"
                ),
                treatment: treatment.sketchCornerTreatment
            )
        }
    }

    private func decodedAdjacentTarget() throws -> SelectionTarget? {
        guard adjacentTarget != nil || adjacentTargetFile != nil else {
            return nil
        }
        return try CLISelectionInputParser.decodeSingleSelectionInput(
            inlinePayload: adjacentTarget,
            filePath: adjacentTargetFile,
            valueName: "Adjacent SelectionTarget"
        )
    }
}
