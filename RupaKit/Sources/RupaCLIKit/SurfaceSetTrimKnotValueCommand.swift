import ArgumentParser
import Foundation
import RupaCore

public struct SurfaceSetTrimKnotValueCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "set-trim-knot-value",
        abstract: "Set an editable source-owned B-spline surface trim p-curve knot value."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @Option(help: "SelectionReference JSON object for one authored B-spline surface trim edge.")
    public var reference: String?

    @Option(help: "JSON file containing one SelectionReference object.")
    public var referenceFile: String?

    @Option(parsing: .unconditional, help: "B-spline trim p-curve knot index from surfaceSourceSummary.")
    public var knotIndex: Int

    @Option(parsing: .unconditional, help: "Target trim p-curve knot scalar value.")
    public var value: Double

    public init() {}

    public func run() async throws {
        let trimReference: SelectionReference = try CLISelectionInputParser.decodeSingleSelectionInput(
            inlinePayload: reference,
            filePath: referenceFile,
            valueName: "SelectionReference"
        )
        let valueExpression = try CLIExpressionParser.scalar(
            value: value,
            valueName: "Surface trim p-curve knot value"
        )

        try await CLIAutomationCommandRunner.run(
            document: document,
            command: .setSurfaceTrimKnotValue(
                target: trimReference,
                knotIndex: knotIndex,
                value: valueExpression
            )
        )
    }
}
