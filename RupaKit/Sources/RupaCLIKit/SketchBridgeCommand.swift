import ArgumentParser
import RupaAutomation
import RupaCore

public struct SketchBridgeCommand: ParsableCommand {
    public enum ContinuityLevel: String, ExpressibleByArgument, Sendable {
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
    public var continuity: ContinuityLevel = .g1

    @Option(help: "First endpoint continuity override: g0, g1, g2, or g3.")
    public var firstContinuity: ContinuityLevel?

    @Option(help: "Second endpoint continuity override: g0, g1, g2, or g3.")
    public var secondContinuity: ContinuityLevel?

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
                firstEndpoint: try decodedEndpoint(
                    inlinePayload: firstEndpoint,
                    filePath: firstEndpointFile,
                    valueName: "First BridgeCurveEndpoint"
                ),
                secondEndpoint: try decodedEndpoint(
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

    private func decodedEndpoint(
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
}
