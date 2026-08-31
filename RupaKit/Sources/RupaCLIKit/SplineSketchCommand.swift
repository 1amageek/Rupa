import ArgumentParser
import RupaCore

public struct SplineSketchCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "spline",
        abstract: "Create a cubic Bezier spline sketch."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @Option(help: "Feature name.")
    public var name: String = "Spline Sketch"

    @Option(
        name: .customLong("control-point"),
        help: "Control point as x,y. Repeat; count must be 3n + 1 and at least 4."
    )
    public var controlPoints: [CLISketchPointArgument] = []

    @Option(help: "Length unit for control point coordinates. Defaults to the workspace display unit.")
    public var unit: LengthDisplayUnit?

    @Option(help: "Sketch plane: xy, yz, or zx. Defaults to the active construction plane.")
    public var plane: CLISketchPlane?

    @Option(help: "Saved construction plane UUID. Cannot be combined with --plane.")
    public var constructionPlaneID: String?

    public init() {}

    public func run() async throws {
        try await CLIAutomationCommandRunner.run(document: document) { sessionID in
            let lengthUnit = try await CLILengthUnitResolver.resolve(
                unit: unit,
                document: document,
                sessionID: sessionID
            )
            let spline = try sketchSpline(unit: lengthUnit)
            return .createSplineSketch(
                name: name,
                plane: try CLISketchPlaneReferenceParser.reference(plane: plane, constructionPlaneID: constructionPlaneID),
                spline: spline
            )
        }
    }

    private func sketchSpline(
        unit lengthUnit: LengthDisplayUnit
    ) throws -> SketchSpline {
        let count = controlPoints.count
        guard count >= 4, (count - 1).isMultiple(of: 3) else {
            throw ValidationError("Spline control point count must be 3n + 1 and at least 4.")
        }
        return SketchSpline(
            controlPoints: try controlPoints.map { point in
                try point.sketchPoint(unit: lengthUnit)
            }
        )
    }
}
