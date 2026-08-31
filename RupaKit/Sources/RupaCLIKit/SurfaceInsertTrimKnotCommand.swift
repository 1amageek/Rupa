import ArgumentParser
import Foundation
import RupaCore

public struct SurfaceInsertTrimKnotCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "insert-trim-knot",
        abstract: "Insert a shape-preserving knot into a source-owned B-spline surface trim p-curve."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @Option(help: "SelectionReference JSON object for one authored B-spline surface trim edge.")
    public var reference: String?

    @Option(help: "JSON file containing one SelectionReference object.")
    public var referenceFile: String?

    @Option(parsing: .unconditional, help: "Inserted trim p-curve knot scalar value.")
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
            valueName: "Surface trim p-curve knot insertion value"
        )

        try await CLIAutomationCommandRunner.run(
            document: document,
            command: .insertSurfaceTrimKnot(
                target: trimReference,
                value: valueExpression
            )
        )
    }
}
