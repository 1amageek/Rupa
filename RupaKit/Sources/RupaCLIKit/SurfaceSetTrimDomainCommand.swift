import ArgumentParser
import Foundation
import RupaAgentRuntime
import RupaCore

public struct SurfaceSetTrimDomainCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "set-trim-domain",
        abstract: "Set a direct B-spline surface rectangular outer trim domain."
    )

    @Argument(help: "Path to the .swcad document for file or auto mode.")
    public var file: String?

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

    @Option(help: "Edit mode: auto, file, or live.")
    public var mode: CLIEditMode = .auto

    @Option(help: "Open document session UUID for live mode.")
    public var sessionID: String?

    @Option(help: "Expected document generation for live mode.")
    public var expectedGeneration: UInt64?

    @Flag(help: "Validate the command without saving the changed file.")
    public var dryRun: Bool = false

    @Flag(help: "Allow direct file mutation even if the app reports the same file as open.")
    public var forceFileEdit: Bool = false

    @Option(help: "Optional Rupa agent socket used to detect open document conflicts.")
    public var agentSocket: String?

    @Flag(help: "Print a JSON result.")
    public var json: Bool = false

    public init() {}

    public func run() throws {
        let id = try CLISelectionInputParser.optionalSessionID(sessionID)
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

        try CLIExitCode.run {
            let agentClient = CLIAgentClientFactory.makeAgentClient(
                mode: mode,
                sessionID: id,
                socket: agentSocket
            )
            let response = try CLIService().setSurfaceTrimDomain(
                target: CLIDocumentTarget(
                    fileURL: file.map(URL.init(fileURLWithPath:)),
                    sessionID: id
                ),
                reference: surfaceReference,
                uLowerBound: uLowerExpression,
                uUpperBound: uUpperExpression,
                vLowerBound: vLowerExpression,
                vUpperBound: vUpperExpression,
                mode: mode,
                expectedGeneration: expectedGeneration.map(DocumentGeneration.init),
                dryRun: dryRun,
                forceFileEdit: forceFileEdit,
                client: agentClient
            )
            try CLIOutput.write(response: response, asJSON: json)
        }
    }
}
