import ArgumentParser
import Foundation
import RupaCore

public struct SurfaceSetTrimDomainCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "set-trim-domain",
        abstract: "Set a direct B-spline surface rectangular outer trim domain."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @Option(help: "SelectionReference JSON object for one direct B-spline surface reference.")
    public var reference: String?

    @Option(help: "JSON file containing one SelectionReference object.")
    public var referenceFile: String?

    @Option(parsing: .unconditional, help: "Lower U parameter bound.")
    public var uLower: Double

    @Option(parsing: .unconditional, help: "Upper U parameter bound.")
    public var uUpper: Double

    @Option(parsing: .unconditional, help: "Lower V parameter bound.")
    public var vLower: Double

    @Option(parsing: .unconditional, help: "Upper V parameter bound.")
    public var vUpper: Double

    public init() {}

    public func run() async throws {
        let surfaceReference: SelectionReference = try CLISelectionInputParser.decodeSingleSelectionInput(
            inlinePayload: reference,
            filePath: referenceFile,
            valueName: "SelectionReference"
        )
        let uLowerExpression = try CLIExpressionParser.scalar(
            value: uLower,
            valueName: "Surface trim domain U lower bound"
        )
        let uUpperExpression = try CLIExpressionParser.scalar(
            value: uUpper,
            valueName: "Surface trim domain U upper bound"
        )
        let vLowerExpression = try CLIExpressionParser.scalar(
            value: vLower,
            valueName: "Surface trim domain V lower bound"
        )
        let vUpperExpression = try CLIExpressionParser.scalar(
            value: vUpper,
            valueName: "Surface trim domain V upper bound"
        )

        try await CLIAutomationCommandRunner.run(
            document: document,
            command: .setSurfaceTrimDomain(
                target: surfaceReference,
                uLowerBound: uLowerExpression,
                uUpperBound: uUpperExpression,
                vLowerBound: vLowerExpression,
                vUpperBound: vUpperExpression
            )
        )
    }
}
