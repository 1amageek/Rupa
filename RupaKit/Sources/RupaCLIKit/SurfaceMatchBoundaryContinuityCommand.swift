import ArgumentParser
import Foundation
import RupaCore

public struct SurfaceMatchBoundaryContinuityCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "match-boundary-continuity",
        abstract: "Match a direct B-spline surface trim boundary to another trim boundary."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

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

    public init() {}

    public func run() async throws {
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

        try await CLIAutomationCommandRunner.run(
            document: document,
            command: .matchSurfaceBoundaryContinuity(
                target: targetReference,
                reference: referenceReference,
                level: level,
                matchSide: matchSide,
                referenceDirection: referenceDirection
            )
        )
    }
}
