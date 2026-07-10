import ArgumentParser
import RupaCore

extension PolygonSizingMode: ExpressibleByArgument {}
extension PolygonInclinationMode: ExpressibleByArgument {}

public struct PolygonSketchCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "polygon",
        abstract: "Create a regular polygon sketch."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @Option(help: "Feature name.")
    public var name: String = "Polygon Sketch"

    @Option(parsing: .unconditional, help: "Polygon center X numeric literal.")
    public var centerX: Double

    @Option(parsing: .unconditional, help: "Polygon center Y numeric literal.")
    public var centerY: Double

    @Option(parsing: .unconditional, help: "Polygon radius numeric literal.")
    public var radius: Double

    @Option(parsing: .unconditional, help: "Polygon side count.")
    public var sides: Int = PolygonToolState.defaultSideCount

    @Option(help: "Length unit for center coordinates and radius. Defaults to the workspace display unit.")
    public var unit: LengthDisplayUnit?

    @Option(help: "Sketch plane: xy, yz, or zx. Defaults to the active construction plane.")
    public var plane: CLISketchPlane?

    @Option(help: "Saved construction plane UUID. Cannot be combined with --plane.")
    public var constructionPlaneID: String?

    @Option(help: "Radius interpretation: circumradius or inradius.")
    public var sizingMode: PolygonSizingMode = .circumradius

    @Option(help: "Initial polygon orientation: vertical or horizontal.")
    public var inclinationMode: PolygonInclinationMode = .vertical

    @Option(parsing: .unconditional, help: "Additional rotation angle numeric literal.")
    public var rotationAngle: Double = 0.0

    @Option(help: "Angle unit for rotation: degree or radian.")
    public var angleUnit: String = AngleUnit.degree.rawValue

    public init() {}

    public func run() throws {
        let sessionID = try document.resolvedSessionID()

        try CLIExitCode.run {
            let lengthUnit = try CLILengthUnitResolver.resolve(
                unit: unit,
                document: document,
                sessionID: sessionID
            )
            let input = try polygonInput(unit: lengthUnit)
            let response = try CLIService().createPolygonSketch(
                target: try document.target(sessionID: sessionID),
                name: name,
                plane: try CLISketchPlaneReferenceParser.reference(plane: plane, constructionPlaneID: constructionPlaneID),
                center: input.center,
                radius: input.radius,
                sides: sides,
                sizingMode: sizingMode,
                inclinationMode: inclinationMode,
                rotationAngle: input.rotationAngle,
                mode: document.mode,
                expectedGeneration: document.generation(),
                dryRun: document.dryRun,
                writePolicy: try document.writePolicy(sessionID: sessionID),
                forceFileEdit: document.forceFileEdit,
                client: document.agentClient(sessionID: sessionID)
            )
            try CLIOutput.write(response: response, asJSON: document.json)
        }
    }

    private func polygonInput(
        unit lengthUnit: LengthDisplayUnit
    ) throws -> (
        center: SketchPoint,
        radius: CADExpression,
        rotationAngle: CADExpression
    ) {
        guard PolygonToolState.isValidSideCount(sides) else {
            throw ValidationError(PolygonToolState.Failure.invalidSideCount(sides).message)
        }
        return (
            center: SketchPoint(
                x: try CLIExpressionParser.length(value: centerX, unit: lengthUnit, valueName: "Polygon center x"),
                y: try CLIExpressionParser.length(value: centerY, unit: lengthUnit, valueName: "Polygon center y")
            ),
            radius: try CLIExpressionParser.length(value: radius, unit: lengthUnit, valueName: "Polygon radius"),
            rotationAngle: try CLIExpressionParser.angle(
                value: rotationAngle,
                unitName: angleUnit,
                valueName: "Polygon rotation angle"
            )
        )
    }
}
