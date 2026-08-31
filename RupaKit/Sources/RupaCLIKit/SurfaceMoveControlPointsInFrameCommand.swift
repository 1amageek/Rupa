import ArgumentParser
import Foundation
import RupaCore

public struct SurfaceMoveControlPointsInFrameCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "move-control-points-in-frame",
        abstract: "Move source-owned surface control points along a resolved UVN surface frame."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

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

    @Option(help: "Length unit for frame distances. Defaults to the workspace display unit.")
    public var unit: String?

    public init() {}

    public func run() async throws {
        let references = try decodedReferences()
        let resolvedFrameQuery = try decodedFrameQuery()

        try await CLIAutomationCommandRunner.run(document: document) { sessionID in
            let lengthUnit = try await CLILengthUnitResolver.resolve(
                unitName: unit,
                document: document,
                sessionID: sessionID
            )
            let distances = distanceExpressions(unit: lengthUnit)
            return .moveSurfaceControlPointsInFrame(
                targets: references,
                frame: resolvedFrameQuery,
                uDistance: distances.u,
                vDistance: distances.v,
                normalDistance: distances.normal
            )
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
