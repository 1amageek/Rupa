import ArgumentParser
import RupaCore

public struct ArcSketchCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "arc",
        abstract: "Create an arc sketch."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @Option(help: "Feature name.")
    public var name: String = "Arc Sketch"

    @Option(parsing: .unconditional, help: "Arc center X numeric literal.")
    public var centerX: Double

    @Option(parsing: .unconditional, help: "Arc center Y numeric literal.")
    public var centerY: Double

    @Option(parsing: .unconditional, help: "Arc radius numeric literal.")
    public var radius: Double

    @Option(parsing: .unconditional, help: "Arc start angle numeric literal.")
    public var startAngle: Double

    @Option(parsing: .unconditional, help: "Arc end angle numeric literal.")
    public var endAngle: Double

    @Option(help: "Length unit for center coordinates and radius. Defaults to the document display unit.")
    public var unit: LengthDisplayUnit?

    @Option(help: "Angle unit for start and end: degree or radian.")
    public var angleUnit: String = AngleUnit.degree.rawValue

    @Option(help: "Sketch plane: xy, yz, or zx. Defaults to the active construction plane.")
    public var plane: CLISketchPlane?

    @Option(help: "Saved construction plane UUID. Cannot be combined with --plane.")
    public var constructionPlaneID: String?

    public init() {}

    public func run() throws {
        let sessionID = try document.resolvedSessionID()

        try CLIExitCode.run {
            let lengthUnit = try CLILengthUnitResolver.resolve(
                unit: unit,
                document: document,
                sessionID: sessionID
            )
            let input = try arcInput(unit: lengthUnit)
            let response = try CLIService().createArcSketch(
                target: document.target(sessionID: sessionID),
                name: name,
                plane: try CLISketchPlaneReferenceParser.reference(plane: plane, constructionPlaneID: constructionPlaneID),
                center: input.center,
                radius: input.radius,
                startAngle: input.startAngle,
                endAngle: input.endAngle,
                mode: document.mode,
                expectedGeneration: document.generation(),
                dryRun: document.dryRun,
                forceFileEdit: document.forceFileEdit,
                client: document.agentClient(sessionID: sessionID)
            )
            try CLIOutput.write(response: response, asJSON: document.json)
        }
    }

    private func arcInput(
        unit lengthUnit: LengthDisplayUnit
    ) throws -> (
        center: SketchPoint,
        radius: CADExpression,
        startAngle: CADExpression,
        endAngle: CADExpression
    ) {
        (
            center: SketchPoint(
                x: try CLIExpressionParser.length(value: centerX, unit: lengthUnit, valueName: "Arc center x"),
                y: try CLIExpressionParser.length(value: centerY, unit: lengthUnit, valueName: "Arc center y")
            ),
            radius: try CLIExpressionParser.length(value: radius, unit: lengthUnit, valueName: "Arc radius"),
            startAngle: try CLIExpressionParser.angle(
                value: startAngle,
                unitName: angleUnit,
                valueName: "Arc start angle"
            ),
            endAngle: try CLIExpressionParser.angle(
                value: endAngle,
                unitName: angleUnit,
                valueName: "Arc end angle"
            )
        )
    }
}
