import ArgumentParser
import Foundation
import RupaCore

public struct SurfaceSetKnotValueCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "set-knot-value",
        abstract: "Set an editable source-owned B-spline surface knot value."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @Option(help: "SelectionReference JSON object for one surface knot.")
    public var reference: String?

    @Option(help: "JSON file containing one SelectionReference object.")
    public var referenceFile: String?

    @Option(parsing: .unconditional, help: "Knot scalar value.")
    public var value: Double

    public init() {}

    public func run() async throws {
        let knotReference: SelectionReference = try CLISelectionInputParser.decodeSingleSelectionInput(
            inlinePayload: reference,
            filePath: referenceFile,
            valueName: "SelectionReference"
        )
        let valueExpression = try CLIExpressionParser.scalar(
            value: value,
            valueName: "Surface knot value"
        )

        try await CLIAutomationCommandRunner.run(
            document: document,
            command: .setSurfaceKnotValue(
                target: knotReference,
                value: valueExpression
            )
        )
    }
}
