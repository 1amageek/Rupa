import ArgumentParser
import RupaAutomation
import RupaCore

public struct SketchOffsetCommand: ParsableCommand {
    public enum VertexHandle: String, ExpressibleByArgument, Sendable {
        case lineStart
        case lineEnd
        case arcStart
        case arcEnd

        var pointHandle: SketchEntityPointHandle {
            switch self {
            case .lineStart:
                .lineStart
            case .lineEnd:
                .lineEnd
            case .arcStart:
                .arcStart
            case .arcEnd:
                .arcEnd
            }
        }
    }

    public static let configuration = CommandConfiguration(
        commandName: "offset",
        abstract: "Offset a supported source curve, region, generated face, generated edge, or vertex target."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @OptionGroup
    public var selection: CLISelectionTargetOptions

    @OptionGroup
    public var options: CLIOffsetCurveOptions

    @Option(help: "Offset distance numeric literal.")
    public var distance: Double

    @Option(help: "Length unit for the offset distance. Defaults to the document display unit.")
    public var unit: String?

    @Option(help: "Optional source endpoint handle for Offset Vertex dispatch: lineStart, lineEnd, arcStart, or arcEnd.")
    public var vertexHandle: VertexHandle?

    public init() {}

    public func run() throws {
        try CLIAutomationCommandRunner.run(document: document) { sessionID in
            let lengthUnit = try CLIAutomationCommandRunner.lengthUnit(
                unitName: unit,
                document: document,
                sessionID: sessionID
            )
            return .offsetCurve(
                target: try selection.decodedTarget(),
                distance: try CLIAutomationCommandRunner.lengthExpression(
                    value: distance,
                    unit: lengthUnit,
                    valueName: "Offset distance"
                ),
                options: try options.options(),
                vertexHandle: vertexHandle?.pointHandle
            )
        }
    }
}
