import ArgumentParser
import Foundation
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

    @Option(parsing: .unconditional, help: "Target dimension value numeric literal.")
    public var targetValue: Double

    @Option(help: "Length unit for distance dimensions. Defaults to the document display unit.")
    public var lengthUnit: LengthDisplayUnit?

    @Option(help: "Angle unit for angle dimensions: degree or radian. Defaults to degree.")
    public var angleUnit: String = AngleUnit.degree.rawValue

    public init() {}

    public func run() throws {
        let sessionID = try document.resolvedSessionID()
        let id = try CLISelectionDimensionReferenceParser.dimensionID(
            dimensionID,
            valueName: "SelectionDimensionID"
        )

        try CLIExitCode.run {
            let targetExpression = try expression(sessionID: sessionID)
            let response = try CLIService().setSelectionDimensionTarget(
                target: try document.target(sessionID: sessionID),
                id: id,
                targetValue: targetExpression,
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

    private func expression(sessionID: UUID?) throws -> CADExpression {
        switch kind {
        case .distance:
            let resolvedLengthUnit = try CLILengthUnitResolver.resolve(
                unit: lengthUnit,
                document: document,
                sessionID: sessionID
            )
            return try CLIExpressionParser.length(
                value: targetValue,
                unit: resolvedLengthUnit,
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
