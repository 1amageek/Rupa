import ArgumentParser
import RupaCore

public struct CLIOffsetCurveOptions: ParsableArguments {
    public enum Mode: String, ExpressibleByArgument, Sendable {
        case offset
        case slot

        var offsetCurveMode: OffsetCurveMode {
            switch self {
            case .offset:
                .offset
            case .slot:
                .slot
            }
        }
    }

    public enum GapFill: String, ExpressibleByArgument, Sendable {
        case round
        case linear
        case natural

        var offsetCurveGapFill: OffsetCurveGapFill {
            switch self {
            case .round:
                .round
            case .linear:
                .linear
            case .natural:
                .natural
            }
        }
    }

    @Option(name: .customLong("offset-mode"), help: "Offset dispatcher mode: offset or slot.")
    public var mode: Mode = .offset

    @Flag(help: "Create symmetric output around the source curve or region.")
    public var symmetric: Bool = false

    @Option(help: "Gap-fill policy: round, linear, or natural.")
    public var gapFill: GapFill = .round

    @Option(help: "Optional support SelectionTarget JSON object for generated edge offsets.")
    public var supportTarget: String?

    @Option(help: "JSON file containing one optional support SelectionTarget object.")
    public var supportTargetFile: String?

    public init() {}

    public func options() throws -> OffsetCurveOptions {
        let support = try decodedSupportTarget()
        return OffsetCurveOptions(
            mode: mode.offsetCurveMode,
            isSymmetric: symmetric,
            gapFill: gapFill.offsetCurveGapFill,
            supportTarget: support
        )
    }

    private func decodedSupportTarget() throws -> SelectionTarget? {
        guard supportTarget != nil || supportTargetFile != nil else {
            return nil
        }
        return try CLISelectionInputParser.decodeSingleSelectionInput(
            inlinePayload: supportTarget,
            filePath: supportTargetFile,
            valueName: "Support SelectionTarget"
        )
    }
}
