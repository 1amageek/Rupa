import ArgumentParser
import Foundation
import RupaCore

public struct SurfaceInsertKnotCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "insert-knot",
        abstract: "Insert or duplicate an editable source-owned B-spline surface knot."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @Option(help: "SelectionReference JSON object for one surface span or knot.")
    public var reference: String?

    @Option(help: "JSON file containing one SelectionReference object.")
    public var referenceFile: String?

    @Option(parsing: .unconditional, help: "Inserted knot scalar value.")
    public var value: Double

    public init() {}

    public func run() async throws {
        let insertionReference: SelectionReference = try CLISelectionInputParser.decodeSingleSelectionInput(
            inlinePayload: reference,
            filePath: referenceFile,
            valueName: "SelectionReference"
        )
        let valueExpression = try CLIExpressionParser.scalar(
            value: value,
            valueName: "Surface knot insertion value"
        )

        try await CLIAutomationCommandRunner.run(
            document: document,
            command: .insertSurfaceKnot(
                target: insertionReference,
                value: valueExpression
            )
        )
    }
}
