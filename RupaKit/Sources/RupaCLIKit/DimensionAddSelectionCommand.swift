import ArgumentParser
import Foundation
import RupaCore

public struct DimensionAddSelectionCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "add-selection",
        abstract: "Add a persistent distance or angle dimension between two SelectionTarget values."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @Option(help: "Optional dimension name.")
    public var name: String?

    @Option(help: "Selection dimension kind: distance or angle.")
    public var kind: CLISelectionDimensionKind

    @Option(help: "First SelectionTarget JSON object.")
    public var firstTarget: String?

    @Option(help: "JSON file containing the first SelectionTarget object.")
    public var firstTargetFile: String?

    @Option(help: "Second SelectionTarget JSON object.")
    public var secondTarget: String?

    @Option(help: "JSON file containing the second SelectionTarget object.")
    public var secondTargetFile: String?

    @Option(parsing: .unconditional, help: "Target dimension value numeric literal.")
    public var targetValue: Double

    @Option(help: "Length unit for distance dimensions. Defaults to the workspace display unit.")
    public var lengthUnit: LengthDisplayUnit?

    @Option(help: "Angle unit for angle dimensions: degree or radian. Defaults to degree.")
    public var angleUnit: String = AngleUnit.degree.rawValue

    public init() {}

    public func run() throws {
        let sessionID = try document.resolvedSessionID()
        let first = try decodedFirstTarget()
        let second = try decodedSecondTarget()

        try CLIExitCode.run {
            let targetExpression = try expression(sessionID: sessionID)
            let response = try CLIService().addSelectionDimension(
                target: try document.target(sessionID: sessionID),
                name: name,
                kind: kind.selectionDimensionKind,
                first: first,
                second: second,
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

    private func decodedFirstTarget() throws -> SelectionTarget {
        try CLISelectionInputParser.decodeSingleSelectionInput(
            inlinePayload: firstTarget,
            filePath: firstTargetFile,
            valueName: "First SelectionTarget"
        )
    }

    private func decodedSecondTarget() throws -> SelectionTarget {
        try CLISelectionInputParser.decodeSingleSelectionInput(
            inlinePayload: secondTarget,
            filePath: secondTargetFile,
            valueName: "Second SelectionTarget"
        )
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
