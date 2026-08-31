import ArgumentParser
import Foundation
import RupaCore

public struct SurfaceSplitSpanCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "split-span",
        abstract: "Split an editable source-owned B-spline surface span by normalized fraction."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @Option(help: "SelectionReference JSON object for one surface span.")
    public var reference: String?

    @Option(help: "JSON file containing one SelectionReference object.")
    public var referenceFile: String?

    @Option(parsing: .unconditional, help: "Normalized split fraction inside the span.")
    public var fraction: Double = 0.5

    public init() {}

    public func run() async throws {
        let spanReference: SelectionReference = try CLISelectionInputParser.decodeSingleSelectionInput(
            inlinePayload: reference,
            filePath: referenceFile,
            valueName: "SelectionReference"
        )
        let fractionExpression = try CLIExpressionParser.scalar(
            value: fraction,
            valueName: "Surface span split fraction"
        )

        try await CLIAutomationCommandRunner.run(
            document: document,
            command: .splitSurfaceSpan(
                target: spanReference,
                fraction: fractionExpression
            )
        )
    }
}
