import ArgumentParser
import RupaCore

public struct DimensionSetSelectionCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "set-selection",
        abstract: "Set the target value of one persistent selection dimension by SelectionDimensionID."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @Option(help: "SelectionDimensionID UUID.")
    public var dimensionID: String

    @Option(help: "Selection dimension kind used to parse the target value: distance or angle.")
    public var kind: CLISelectionDimensionKind

    @Option(help: "Target dimension value numeric literal.")
    public var targetValue: Double

    @Option(help: "Length unit for distance dimensions. Defaults to millimeter.")
    public var lengthUnit: LengthDisplayUnit = .millimeter

    @Option(help: "Angle unit for angle dimensions: degree or radian. Defaults to degree.")
    public var angleUnit: String = AngleUnit.degree.rawValue

    public init() {}

    public func run() throws {
        let sessionID = try document.resolvedSessionID()
        let id = try CLISelectionDimensionReferenceParser.dimensionID(
            dimensionID,
            valueName: "SelectionDimensionID"
        )
        let targetExpression = try expression()

        try CLIExitCode.run {
            let response = try CLIService().setSelectionDimensionTarget(
                target: document.target(sessionID: sessionID),
                id: id,
                targetValue: targetExpression,
                mode: document.mode,
                expectedGeneration: document.generation(),
                dryRun: document.dryRun,
                forceFileEdit: document.forceFileEdit,
                client: document.agentClient(sessionID: sessionID)
            )
            try CLIOutput.write(response: response, asJSON: document.json)
        }
    }

    private func expression() throws -> CADExpression {
        switch kind {
        case .distance:
            return try CLIExpressionParser.length(
                value: targetValue,
                unit: lengthUnit,
                valueName: "Selection dimension target value"
            )
        case .angle:
            return try CLIExpressionParser.angle(
                value: targetValue,
                unitName: angleUnit,
                valueName: "Selection dimension target value"
            )
        }
    }
}
