import ArgumentParser
import Foundation
import RupaCore

public struct SurfaceMoveTrimEndpointCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "move-trim-endpoint",
        abstract: "Move a source-owned authored direct B-spline surface trim endpoint."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @Option(help: "SelectionReference JSON object for one authored surface trim edge.")
    public var reference: String?

    @Option(help: "JSON file containing one SelectionReference object.")
    public var referenceFile: String?

    @Option(help: "Trim endpoint to move: start or end.")
    public var endpoint: SurfaceTrimEndpoint = .end

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
            valueName: "Surface trim endpoint U parameter"
        )
        let vExpression = try CLIExpressionParser.scalar(
            value: v,
            valueName: "Surface trim endpoint V parameter"
        )

        try await CLIAutomationCommandRunner.run(
            document: document,
            command: .moveSurfaceTrimEndpoint(
                target: trimReference,
                endpoint: endpoint,
                u: uExpression,
                v: vExpression
            )
        )
    }
}
