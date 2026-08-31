import ArgumentParser
import Foundation
import RupaCore

public struct SurfaceMoveTrimControlPointCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "move-trim-control-point",
        abstract: "Move a source-owned authored direct B-spline surface trim p-curve interior control point."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @Option(help: "SelectionReference JSON object for one authored surface trim edge.")
    public var reference: String?

    @Option(help: "JSON file containing one SelectionReference object.")
    public var referenceFile: String?

    @Option(parsing: .unconditional, help: "Strict interior p-curve control point index.")
    public var controlPointIndex: Int

    @Option(parsing: .unconditional, help: "Target U parameter.")
    public var u: Double

    @Option(parsing: .unconditional, help: "Target V parameter.")
    public var v: Double

    public init() {}

    public func run() async throws {
        let trimReference: SelectionReference = try CLISelectionInputParser.decodeSingleSelectionInput(
            inlinePayload: reference,
            filePath: referenceFile,
            valueName: "SelectionReference"
        )
        let uExpression = try CLIExpressionParser.scalar(
            value: u,
            valueName: "Surface trim control point U parameter"
        )
        let vExpression = try CLIExpressionParser.scalar(
            value: v,
            valueName: "Surface trim control point V parameter"
        )

        try await CLIAutomationCommandRunner.run(
            document: document,
            command: .moveSurfaceTrimControlPoint(
                target: trimReference,
                controlPointIndex: controlPointIndex,
                u: uExpression,
                v: vExpression
            )
        )
    }
}
