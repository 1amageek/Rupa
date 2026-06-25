import ArgumentParser
import Foundation
import RupaAutomation
import RupaCore

public enum CLIBridgeContinuityLevel: String, ExpressibleByArgument, Sendable {
    case g0
    case g1
    case g2
    case g3

    public var endpointContinuity: BridgeCurveEndpointContinuity {
        switch self {
        case .g0:
            .g0
        case .g1:
            .g1
        case .g2:
            .g2
        case .g3:
            .g3
        }
    }
}

public struct SketchBridgeCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "bridge",
        abstract: "Create a bridge curve in an editable sketch feature."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @Option(help: "Sketch feature UUID that owns the generated bridge entity.")
    public var featureID: String

    @Option(help: "First BridgeCurveEndpoint JSON object.")
    public var firstEndpoint: String?

    @Option(help: "JSON file containing one first BridgeCurveEndpoint object.")
    public var firstEndpointFile: String?

    @Option(help: "Second BridgeCurveEndpoint JSON object.")
    public var secondEndpoint: String?

    @Option(help: "JSON file containing one second BridgeCurveEndpoint object.")
    public var secondEndpointFile: String?

    @Option(help: "Continuity level for both endpoints: g0, g1, g2, or g3.")
    public var continuity: CLIBridgeContinuityLevel = .g1

    @Option(help: "First endpoint continuity override: g0, g1, g2, or g3.")
    public var firstContinuity: CLIBridgeContinuityLevel?

    @Option(help: "Second endpoint continuity override: g0, g1, g2, or g3.")
    public var secondContinuity: CLIBridgeContinuityLevel?

    @Flag(help: "Trim source curves to the resolved bridge endpoints before creating the bridge.")
    public var trimsSourceCurves: Bool = false

    public init() {}

    public func run() throws {
        try CLIAutomationCommandRunner.run(
            document: document,
            command: .createBridgeCurve(
                featureID: try CLIFeatureReferenceParser.featureID(
                    featureID,
                    valueName: "Bridge sketch feature ID"
                ),
                firstEndpoint: try CLIBridgeEndpointInputParser.decodeRequiredEndpoint(
                    inlinePayload: firstEndpoint,
                    filePath: firstEndpointFile,
                    valueName: "First BridgeCurveEndpoint"
                ),
                secondEndpoint: try CLIBridgeEndpointInputParser.decodeRequiredEndpoint(
                    inlinePayload: secondEndpoint,
                    filePath: secondEndpointFile,
                    valueName: "Second BridgeCurveEndpoint"
                ),
                continuity: BridgeCurveContinuity(
                    first: (firstContinuity ?? continuity).endpointContinuity,
                    second: (secondContinuity ?? continuity).endpointContinuity
                ),
                trimsSourceCurves: trimsSourceCurves
            )
        )
    }
}

public struct SketchBridgeUpdateCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "bridge-update",
        abstract: "Update an existing bridge curve source."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @Option(help: "BridgeCurveSource UUID.")
    public var sourceID: String

    @Option(help: "Replacement first BridgeCurveEndpoint JSON object.")
    public var firstEndpoint: String?

    @Option(help: "JSON file containing one replacement first BridgeCurveEndpoint object.")
    public var firstEndpointFile: String?

    @Option(help: "Replacement second BridgeCurveEndpoint JSON object.")
    public var secondEndpoint: String?

    @Option(help: "JSON file containing one replacement second BridgeCurveEndpoint object.")
    public var secondEndpointFile: String?

    @Option(help: "Replacement continuity level for both endpoints: g0, g1, g2, or g3.")
    public var continuity: CLIBridgeContinuityLevel?

    @Option(help: "Replacement first endpoint continuity: g0, g1, g2, or g3.")
    public var firstContinuity: CLIBridgeContinuityLevel?

    @Option(help: "Replacement second endpoint continuity: g0, g1, g2, or g3.")
    public var secondContinuity: CLIBridgeContinuityLevel?

    public init() {}

    public func run() throws {
        let first = try CLIBridgeEndpointInputParser.decodeOptionalEndpoint(
            inlinePayload: firstEndpoint,
            filePath: firstEndpointFile,
            valueName: "First BridgeCurveEndpoint"
        )
        let second = try CLIBridgeEndpointInputParser.decodeOptionalEndpoint(
            inlinePayload: secondEndpoint,
            filePath: secondEndpointFile,
            valueName: "Second BridgeCurveEndpoint"
        )
        let nextContinuity = try updatedContinuity()

        guard first != nil || second != nil || nextContinuity != nil else {
            throw ValidationError("Bridge update requires at least one endpoint or continuity change.")
        }

        try CLIAutomationCommandRunner.run(
            document: document,
            command: .setBridgeCurveParameters(
                sourceID: try parsedSourceID(),
                firstEndpoint: first,
                secondEndpoint: second,
                continuity: nextContinuity,
                trimsSourceCurves: nil
            )
        )
    }

    private func parsedSourceID() throws -> BridgeCurveSourceID {
        guard let uuid = UUID(uuidString: sourceID) else {
            throw ValidationError("BridgeCurveSource ID must be a UUID.")
        }
        return BridgeCurveSourceID(uuid)
    }

    private func updatedContinuity() throws -> BridgeCurveContinuity? {
        guard continuity != nil || firstContinuity != nil || secondContinuity != nil else {
            return nil
        }
        guard let first = firstContinuity ?? continuity,
              let second = secondContinuity ?? continuity else {
            throw ValidationError("Provide --continuity or both --first-continuity and --second-continuity.")
        }
        return BridgeCurveContinuity(
            first: first.endpointContinuity,
            second: second.endpointContinuity
        )
    }
}

private enum CLIBridgeEndpointInputParser {
    static func decodeRequiredEndpoint(
        inlinePayload: String?,
        filePath: String?,
        valueName: String
    ) throws -> BridgeCurveEndpoint {
        try CLISelectionInputParser.decodeSingleSelectionInput(
            inlinePayload: inlinePayload,
            filePath: filePath,
            valueName: valueName
        )
    }

    static func decodeOptionalEndpoint(
        inlinePayload: String?,
        filePath: String?,
        valueName: String
    ) throws -> BridgeCurveEndpoint? {
        guard inlinePayload != nil || filePath != nil else {
            return nil
        }
        return try decodeRequiredEndpoint(
            inlinePayload: inlinePayload,
            filePath: filePath,
            valueName: valueName
        )
    }
}
