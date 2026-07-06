import ArgumentParser
import Foundation
import RupaAgentRuntime
import RupaCore

public struct SurfaceMoveTrimEndpointCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "move-trim-endpoint",
        abstract: "Move a source-owned authored direct B-spline surface trim endpoint."
    )

    @Argument(help: "Path to the .swcad document for file or auto mode.")
    public var file: String?

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

        try CLIExitCode.run {
            let agentClient = CLIAgentClientFactory.makeAgentClient(
                mode: mode,
                sessionID: id,
                socket: agentSocket
            )
            let response = try CLIService().moveSurfaceTrimEndpoint(
                target: CLIDocumentTarget(
                    fileURL: file.map(URL.init(fileURLWithPath:)),
                    sessionID: id
                ),
                reference: trimReference,
                endpoint: endpoint,
                u: uExpression,
                v: vExpression,
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
