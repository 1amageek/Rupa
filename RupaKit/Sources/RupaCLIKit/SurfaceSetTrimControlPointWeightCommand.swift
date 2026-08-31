import ArgumentParser
import Foundation
import RupaCore

public struct SurfaceSetTrimControlPointWeightCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "set-trim-control-point-weight",
        abstract: "Set a source-owned authored direct B-spline surface trim p-curve control point weight."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @Option(help: "SelectionReference JSON object for one authored surface trim edge.")
    public var reference: String?

    @Option(help: "JSON file containing one SelectionReference object.")
    public var referenceFile: String?

    @Option(parsing: .unconditional, help: "B-spline p-curve control point index.")
    public var controlPointIndex: Int

    @Option(parsing: .unconditional, help: "Positive target weight.")
    public var weight: Double

    public init() {}

    public func run() async throws {
        let trimReference: SelectionReference = try CLISelectionInputParser.decodeSingleSelectionInput(
            inlinePayload: reference,
            filePath: referenceFile,
            valueName: "SelectionReference"
        )
        let weightExpression = try CLIExpressionParser.scalar(
            value: weight,
            valueName: "Surface trim control point weight"
        )

        try await CLIAutomationCommandRunner.run(
            document: document,
            command: .setSurfaceTrimControlPointWeight(
                target: trimReference,
                controlPointIndex: controlPointIndex,
                weight: weightExpression
            )
        )
    }
}
