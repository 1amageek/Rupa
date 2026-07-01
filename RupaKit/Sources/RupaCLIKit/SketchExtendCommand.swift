import ArgumentParser
import RupaAutomation
import RupaCore

public struct SketchExtendCommand: ParsableCommand {
    public enum Shape: String, ExpressibleByArgument, Sendable {
        case natural
        case linear
        case soft
        case reflective
        case arc

        var curveShape: ExtendCurveShape {
            switch self {
            case .natural:
                .natural
            case .linear:
                .linear
            case .soft:
                .soft
            case .reflective:
                .reflective
            case .arc:
                .arc
            }
        }
    }

    public static let configuration = CommandConfiguration(
        commandName: "extend",
        abstract: "Extend a supported source sketch curve endpoint."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @OptionGroup
    public var selection: CLISelectionTargetOptions

    @Option(help: "Extension distance numeric literal.")
    public var distance: Double

    @Option(help: "Length unit for the extension distance. Defaults to the document display unit.")
    public var unit: String?

    @Option(help: "Extension shape: natural, linear, soft, reflective, or arc.")
    public var shape: Shape = .natural

    public init() {}

    public func run() throws {
        try CLIAutomationCommandRunner.run(document: document) { sessionID in
            let lengthUnit = try CLIAutomationCommandRunner.lengthUnit(
                unitName: unit,
                document: document,
                sessionID: sessionID
            )
            return .extendSketchCurve(
                target: try selection.decodedTarget(),
                distance: try CLIAutomationCommandRunner.lengthExpression(
                    value: distance,
                    unit: lengthUnit,
                    valueName: "Extension distance"
                ),
                shape: shape.curveShape
            )
        }
    }
}
