import ArgumentParser
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

    @Option(help: "Target dimension value numeric literal.")
    public var targetValue: Double

    @Option(help: "Length unit for distance dimensions. Defaults to millimeter.")
    public var lengthUnit: LengthDisplayUnit = .millimeter

    @Option(help: "Angle unit for angle dimensions: degree or radian. Defaults to degree.")
    public var angleUnit: String = AngleUnit.degree.rawValue

    public init() {}

    public func run() throws {
        let sessionID = try document.resolvedSessionID()
        let first = try decodedFirstTarget()
        let second = try decodedSecondTarget()
        let targetExpression = try expression()

        try CLIExitCode.run {
            let response = try CLIService().addSelectionDimension(
                target: document.target(sessionID: sessionID),
                name: name,
                kind: kind.selectionDimensionKind,
                first: first,
                second: second,
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
