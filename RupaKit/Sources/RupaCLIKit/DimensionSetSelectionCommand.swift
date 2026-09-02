import ArgumentParser
import Foundation
import RupaAgentProtocol
import RupaCore

public struct DimensionSetSelectionCommand: AsyncParsableCommand {
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

    @Option(help: "Length unit for distance dimensions. Defaults to the workspace display unit.")
    public var lengthUnit: LengthDisplayUnit?

    @Option(help: "Angle unit for angle dimensions: degree or radian. Defaults to degree.")
    public var angleUnit: String = AngleUnit.degree.rawValue

    public init() {}

    public func run() async throws {
        let id = try CLISelectionDimensionReferenceParser.dimensionID(
            dimensionID,
            valueName: "SelectionDimensionID"
        )
        let sessionID = try document.resolvedSessionID()

        try await CLIExitCode.run {
            let targetExpression = try await expression(sessionID: sessionID)
            let response = try await CLIService().executeTypedMutationRequest(
                target: document.target(sessionID: sessionID)
            ) { sessionID in
                .setSelectionDimensionTargetExpression(
                    sessionID: sessionID,
                    id: id,
                    expression: targetExpression,
                    defaults: nil,
                    expectedGeneration: document.generation()
                )
            }
            try CLIOutput.write(response: response, asJSON: document.json)
        }
    }

    private func expression(sessionID: UUID?) async throws -> String {
        guard targetValue.isFinite else {
            throw ValidationError("Selection dimension target value must be finite.")
        }
        switch kind {
        case .distance:
            let unit = try await CLILengthUnitResolver.resolve(
                unit: lengthUnit,
                document: document,
                sessionID: sessionID
            )
            return "\(targetValue) \(unit.rawValue)"
        case .angle:
            guard let unit = AngleUnit(rawValue: angleUnit) else {
                throw ValidationError("Angle unit must be degree or radian.")
            }
            return "\(targetValue) \(unit.rawValue)"
        }
    }
}
