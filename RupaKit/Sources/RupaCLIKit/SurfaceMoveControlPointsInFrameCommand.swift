import ArgumentParser
import Foundation
import RupaAgentRuntime
import RupaCore

public struct SurfaceMoveControlPointsInFrameCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "move-control-points-in-frame",
        abstract: "Move source-owned surface control points along a resolved UVN surface frame."
    )

    @Argument(help: "Path to the .swcad document for file or auto mode.")
    public var file: String?

    @Option(
        name: .customLong("reference"),
        help: "SelectionReference JSON object. Repeat to move multiple surface control points."
    )
    public var referencePayloads: [String] = []

    @Option(help: "JSON file containing one SelectionReference object or an array.")
    public var referencesFile: String?

    @Option(
        name: .customLong("frame-query"),
        help: "SurfaceFrameQuery JSON object used to resolve the UVN frame."
    )
    public var frameQuery: String?

    @Option(help: "JSON file containing one SurfaceFrameQuery object.")
    public var frameQueryFile: String?

    @Option(parsing: .unconditional, help: "Distance along the frame U axis.")
    public var uDistance: Double = 0.0

    @Option(parsing: .unconditional, help: "Distance along the frame V axis.")
    public var vDistance: Double = 0.0

    @Option(parsing: .unconditional, help: "Distance along the frame normal axis.")
    public var normalDistance: Double = 0.0

    @Option(help: "Length unit for frame distances. Defaults to the document display unit.")
    public var unit: String?

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
        let references = try decodedReferences()
        let resolvedFrameQuery = try decodedFrameQuery()

        try CLIExitCode.run {
            let agentClient = CLIAgentClientFactory.makeAgentClient(
                mode: mode,
                sessionID: id,
                socket: agentSocket
            )
            let documentTarget = CLIDocumentTarget(
                fileURL: file.map(URL.init(fileURLWithPath:)),
                sessionID: id
            )
            let lengthUnit = try CLILengthUnitResolver.resolve(
                unitName: unit,
                target: documentTarget,
                mode: mode,
                expectedGeneration: expectedGeneration.map(DocumentGeneration.init),
                forceFileEdit: forceFileEdit,
                client: agentClient
            )
            let distances = distanceExpressions(unit: lengthUnit)
            let response = try CLIService().moveSurfaceControlPointsInFrame(
                target: documentTarget,
                references: references,
                frame: resolvedFrameQuery,
                uDistance: distances.u,
                vDistance: distances.v,
                normalDistance: distances.normal,
                mode: mode,
                expectedGeneration: expectedGeneration.map(DocumentGeneration.init),
                dryRun: dryRun,
                forceFileEdit: forceFileEdit,
                client: agentClient
            )
            try CLIOutput.write(response: response, asJSON: json)
        }
    }

    private func decodedReferences() throws -> [SelectionReference] {
        try CLISelectionInputParser.decodeSelectionInput(
            inlinePayloads: referencePayloads,
            filePath: referencesFile,
            clear: false,
            valueName: "SelectionReference",
            arrayName: "SelectionReference"
        )
    }

    private func decodedFrameQuery() throws -> SurfaceFrameQuery {
        try CLISelectionInputParser.decodeSingleSelectionInput(
            inlinePayload: frameQuery,
            filePath: frameQueryFile,
            valueName: "SurfaceFrameQuery"
        )
    }

    private func distanceExpressions(
        unit lengthUnit: LengthDisplayUnit
    ) -> (
        u: CADExpression,
        v: CADExpression,
        normal: CADExpression
    ) {
        return (
            lengthExpression(uDistance, unit: lengthUnit),
            lengthExpression(vDistance, unit: lengthUnit),
            lengthExpression(normalDistance, unit: lengthUnit)
        )
    }

    private func lengthExpression(_ value: Double, unit: LengthDisplayUnit) -> CADExpression {
        .constant(Quantity(value: unit.meters(from: value), kind: .length))
    }
}
