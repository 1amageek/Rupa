import ArgumentParser
import Foundation
import RupaAgentRuntime
import RupaCore

public struct SurfaceMatchBoundaryContinuityCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "match-boundary-continuity",
        abstract: "Match a direct B-spline surface trim boundary to another trim boundary."
    )

    @Argument(help: "Path to the .swcad document for file or auto mode.")
    public var file: String?

    @Option(help: "SelectionReference JSON object for the target surface trim.")
    public var target: String?

    @Option(help: "JSON file containing the target SelectionReference object.")
    public var targetFile: String?

    @Option(help: "SelectionReference JSON object for the reference surface trim.")
    public var reference: String?

    @Option(help: "JSON file containing the reference SelectionReference object.")
    public var referenceFile: String?

    @Option(help: "Continuity level to match: g0, g1, or g2.")
    public var level: SurfaceBoundaryContinuityLevel = .g1

    @Option(help: "Boundary side relation: automatic, same, or opposite.")
    public var matchSide: SurfaceBoundaryMatchSide = .automatic

    @Option(help: "Reference boundary order: automatic, forward, or reversed.")
    public var referenceDirection: SurfaceBoundaryReferenceDirection = .automatic

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

    @OptionGroup
    public var writeDestination: CLIWriteDestinationOptions

    public init() {}

    public func run() throws {
        let id = try CLISelectionInputParser.optionalSessionID(sessionID)
        let targetReference: SelectionReference = try CLISelectionInputParser.decodeSingleSelectionInput(
            inlinePayload: target,
            filePath: targetFile,
            valueName: "Target SelectionReference"
        )
        let referenceReference: SelectionReference = try CLISelectionInputParser.decodeSingleSelectionInput(
            inlinePayload: reference,
            filePath: referenceFile,
            valueName: "Reference SelectionReference"
        )

        try CLIExitCode.run {
            let writePolicy = try writeDestination.writePolicy(file: file, mode: mode, sessionID: id)
            let agentClient = CLIAgentClientFactory.makeAgentClient(
                mode: mode,
                sessionID: id,
                socket: agentSocket
            )
            let response = try CLIService().matchSurfaceBoundaryContinuity(
                target: CLIDocumentTarget(
                    fileURL: file.map(URL.init(fileURLWithPath:)),
                    sessionID: id
                ),
                targetReference: targetReference,
                reference: referenceReference,
                level: level,
                matchSide: matchSide,
                referenceDirection: referenceDirection,
                mode: mode,
                expectedGeneration: expectedGeneration.map(DocumentGeneration.init),
                dryRun: dryRun,
                writePolicy: writePolicy,
                forceFileEdit: forceFileEdit,
                client: agentClient
            )
            try CLIOutput.write(response: response, asJSON: json)
        }
    }
}
