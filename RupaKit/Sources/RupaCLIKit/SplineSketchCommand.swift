import ArgumentParser
import RupaCore

public struct SplineSketchCommand: ParsableCommand {
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

    @Option(help: "Length unit for control point coordinates. Defaults to the document display unit.")
    public var unit: LengthDisplayUnit?

    @Option(help: "Sketch plane: xy, yz, or zx.")
    public var plane: CLISketchPlane = .xy

    public init() {}

    public func run() throws {
        let sessionID = try document.resolvedSessionID()

        try CLIExitCode.run {
            let lengthUnit = try CLILengthUnitResolver.resolve(
                unit: unit,
                document: document,
                sessionID: sessionID
            )
            let spline = try sketchSpline(unit: lengthUnit)
            let response = try CLIService().createSplineSketch(
                target: document.target(sessionID: sessionID),
                name: name,
                plane: plane.sketchPlane,
                spline: spline,
                mode: document.mode,
                expectedGeneration: document.generation(),
                dryRun: document.dryRun,
                forceFileEdit: document.forceFileEdit,
                client: document.agentClient(sessionID: sessionID)
            )
            try CLIOutput.write(response: response, asJSON: document.json)
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
