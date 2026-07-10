import ArgumentParser
import RupaCore

public struct RevolveModelCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "revolve",
        abstract: "Revolve an existing closed sketch profile around an explicit 3D axis."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @Option(help: "Feature name.")
    public var name: String = "Revolve"

    @Option(help: "Closed profile sketch feature UUID used as the revolve profile.")
    public var profileFeatureID: String

    @Option(parsing: .unconditional, help: "Profile index inside the profile feature.")
    public var profileIndex: Int = 0

    @Option(parsing: .unconditional, help: "Axis origin X coordinate.")
    public var axisOriginX: Double = 0.0

    @Option(parsing: .unconditional, help: "Axis origin Y coordinate.")
    public var axisOriginY: Double = 0.0

    @Option(parsing: .unconditional, help: "Axis origin Z coordinate.")
    public var axisOriginZ: Double = 0.0

    @Option(help: "Length unit for axis origin coordinates. Defaults to the workspace display unit.")
    public var axisUnit: String?

    @Option(parsing: .unconditional, help: "Axis direction X component.")
    public var axisDirectionX: Double = 0.0

    @Option(parsing: .unconditional, help: "Axis direction Y component.")
    public var axisDirectionY: Double = 1.0

    @Option(parsing: .unconditional, help: "Axis direction Z component.")
    public var axisDirectionZ: Double = 0.0

    @Option(parsing: .unconditional, help: "Revolve angle numeric literal.")
    public var angle: Double = 360.0

    @Option(help: "Angle unit: degree or radian.")
    public var angleUnit: String = AngleUnit.degree.rawValue

    public init() {}

    public func run() throws {
        let sessionID = try document.resolvedSessionID()

        try CLIExitCode.run {
            let lengthUnit = try CLILengthUnitResolver.resolve(
                unitName: axisUnit,
                document: document,
                sessionID: sessionID
            )
            let input = try revolveInput(axisUnit: lengthUnit)
            let response = try CLIService().createRevolve(
                target: try document.target(sessionID: sessionID),
                name: name,
                profile: input.profile,
                axis: input.axis,
                angle: input.angle,
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

    private func revolveInput(axisUnit lengthUnit: LengthDisplayUnit) throws -> (
        profile: ProfileReference,
        axis: RevolveAxis,
        angle: CADExpression
    ) {
        guard profileIndex >= 0 else {
            throw ValidationError("Profile index must be zero or greater.")
        }
        let profileFeatureID = try CLIFeatureReferenceParser.featureID(
            profileFeatureID,
            valueName: "Profile feature ID"
        )
        let axis = RevolveAxis(
            origin: try CLI3DInputParser.point(
                x: axisOriginX,
                y: axisOriginY,
                z: axisOriginZ,
                unit: lengthUnit,
                valueName: "Revolve axis origin"
            ),
            direction: try CLI3DInputParser.vector(
                x: axisDirectionX,
                y: axisDirectionY,
                z: axisDirectionZ,
                valueName: "Revolve axis direction"
            )
        )
        return (
            profile: ProfileReference(featureID: profileFeatureID, profileIndex: profileIndex),
            axis: axis,
            angle: try CLIExpressionParser.angle(
                value: angle,
                unitName: angleUnit,
                valueName: "Revolve angle"
            )
        )
    }
}
