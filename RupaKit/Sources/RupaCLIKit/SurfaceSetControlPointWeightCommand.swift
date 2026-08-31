import ArgumentParser
import Foundation
import RupaCore

public struct SurfaceSetControlPointWeightCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "set-control-point-weight",
        abstract: "Set a source-owned surface control point weight."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @Option(help: "SelectionReference JSON object for one surface control point.")
    public var reference: String?

    @Option(help: "JSON file containing one SelectionReference object.")
    public var referenceFile: String?

    @Option(parsing: .unconditional, help: "Control point weight scalar value.")
    public var weight: Double

    public init() {}

    public func run() async throws {
        let surfaceReference: SelectionReference = try CLISelectionInputParser.decodeSingleSelectionInput(
            inlinePayload: reference,
            filePath: referenceFile,
            valueName: "SelectionReference"
        )
        let weightExpression = try CLIExpressionParser.scalar(
            value: weight,
            valueName: "Surface control point weight"
        )

        try await CLIAutomationCommandRunner.run(
            document: document,
            command: .setSurfaceControlPointWeight(
                target: surfaceReference,
                weight: weightExpression
            )
        )
    }
}
