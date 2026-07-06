import ArgumentParser
import RupaCore

public struct SweepModelCommand: ParsableCommand {
    public enum Alignment: String, ExpressibleByArgument, Sendable {
        case parallel
        case normal

        var sweepValue: SweepAlignment {
            switch self {
            case .parallel:
                .parallel
            case .normal:
                .normal
            }
        }
    }

    public enum CornerStyle: String, ExpressibleByArgument, Sendable {
        case mitre
        case round

        var sweepValue: SweepCornerStyle {
            switch self {
            case .mitre:
                .mitre
            case .round:
                .round
            }
        }
    }

    public enum GuideMethod: String, ExpressibleByArgument, Sendable {
        case point
        case chord
        case curve

        var sweepValue: SweepGuideMethod {
            switch self {
            case .point:
                .point
            case .chord:
                .chord
            case .curve:
                .curve
            }
        }
    }

    public enum BooleanOperation: String, ExpressibleByArgument, Sendable {
        case newBody
        case union
        case difference
        case intersect
        case slice

        var sweepValue: SweepBooleanOperation {
            switch self {
            case .newBody:
                .newBody
            case .union:
                .union
            case .difference:
                .difference
            case .intersect:
                .intersect
            case .slice:
                .slice
            }
        }
    }

    public enum ResultKind: String, ExpressibleByArgument, Sendable {
        case solid
        case sheet

        var sweepValue: SweepResultKind {
            switch self {
            case .solid:
                .solid
            case .sheet:
                .sheet
            }
        }
    }

    public static let configuration = CommandConfiguration(
        commandName: "sweep",
        abstract: "Sweep a profile or curve section along a path."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @Option(help: "Feature name.")
    public var name: String = "Sweep"

    @Option(help: "Closed profile sketch feature UUID used as the sweep section.")
    public var profileFeatureID: String?

    @Option(parsing: .unconditional, help: "Profile index inside the profile feature.")
    public var profileIndex: Int = 0

    @Option(help: "Curve feature UUID used as a sheet sweep section.")
    public var curveSectionFeatureID: String?

    @Option(help: "Curve feature UUID used as the sweep path.")
    public var pathFeatureID: String

    @Option(name: .customLong("guide-feature-id"), help: "Curve feature UUID used as a sweep guide. Repeatable.")
    public var guideFeatureIDs: [String] = []

    @Option(name: .customLong("target-feature-id"), help: "Body feature UUID used as a boolean target. Repeatable.")
    public var targetFeatureIDs: [String] = []

    @Option(parsing: .unconditional, help: "Twist angle numeric literal.")
    public var twistAngle: Double = 0.0

    @Option(help: "Angle unit for twist: degree or radian.")
    public var angleUnit: String = AngleUnit.degree.rawValue

    @Option(parsing: .unconditional, help: "End scale scalar.")
    public var endScale: Double = 1.0

    @Option(parsing: .unconditional, help: "Path distance fraction, greater than 0 and at most 1.")
    public var distanceFraction: Double = 1.0

    @Option(help: "Sweep alignment: normal or parallel.")
    public var alignment: Alignment = .normal

    @Option(help: "Path corner style: mitre or round.")
    public var cornerStyle: CornerStyle = .mitre

    @Option(help: "Guide method: point, chord, or curve.")
    public var guideMethod: GuideMethod = .point

    @Option(help: "Boolean operation: newBody, union, difference, intersect, or slice.")
    public var booleanOperation: BooleanOperation = .newBody

    @Flag(help: "Keep tool bodies when using a boolean target operation.")
    public var keepTools: Bool = false

    @Flag(help: "Request sweep simplification when supported.")
    public var simplify: Bool = false

    @Option(help: "Sweep result kind: solid or sheet.")
    public var resultKind: ResultKind = .solid

    public init() {}

    public func run() throws {
        let sessionID = try document.resolvedSessionID()
        let input = try sweepInput()

        try CLIExitCode.run {
            let response = try CLIService().createSweep(
                target: document.target(sessionID: sessionID),
                name: name,
                sections: input.sections,
                path: input.path,
                guides: input.guides,
                targets: input.targets,
                options: input.options,
                mode: document.mode,
                expectedGeneration: document.generation(),
                dryRun: document.dryRun,
                forceFileEdit: document.forceFileEdit,
                client: document.agentClient(sessionID: sessionID)
            )
            try CLIOutput.write(response: response, asJSON: document.json)
        }
    }

    private func sweepInput() throws -> (
        sections: [SweepSectionReference],
        path: SweepPathReference,
        guides: [SweepGuideReference],
        targets: [SweepTargetReference],
        options: SweepOptions
    ) {
        guard (profileFeatureID != nil) != (curveSectionFeatureID != nil) else {
            throw ValidationError("Provide exactly one sweep section input.")
        }
        guard profileIndex >= 0 else {
            throw ValidationError("Profile index must be zero or greater.")
        }

        let sections: [SweepSectionReference]
        if let profileFeatureID {
            let featureID = try CLIFeatureReferenceParser.featureID(
                profileFeatureID,
                valueName: "Profile feature ID"
            )
            sections = [.profile(ProfileReference(featureID: featureID, profileIndex: profileIndex))]
        } else if let curveSectionFeatureID {
            let featureID = try CLIFeatureReferenceParser.featureID(
                curveSectionFeatureID,
                valueName: "Curve section feature ID"
            )
            sections = [.curve(SweepCurveSectionReference(featureID: featureID))]
        } else {
            throw ValidationError("Provide a sweep section input.")
        }

        let path = SweepPathReference(
            featureID: try CLIFeatureReferenceParser.featureID(pathFeatureID, valueName: "Path feature ID")
        )
        let guides = try guideFeatureIDs.map { value in
            SweepGuideReference(
                featureID: try CLIFeatureReferenceParser.featureID(value, valueName: "Guide feature ID")
            )
        }
        let targets = try targetFeatureIDs.map { value in
            SweepTargetReference(
                featureID: try CLIFeatureReferenceParser.featureID(value, valueName: "Target feature ID")
            )
        }
        let options = SweepOptions(
            twistAngle: try CLIExpressionParser.angle(
                value: twistAngle,
                unitName: angleUnit,
                valueName: "Sweep twist angle"
            ),
            endScale: try CLIExpressionParser.scalar(value: endScale, valueName: "Sweep end scale"),
            alignment: alignment.sweepValue,
            distanceFraction: try CLIExpressionParser.scalar(
                value: distanceFraction,
                valueName: "Sweep distance fraction"
            ),
            cornerStyle: cornerStyle.sweepValue,
            guideMethod: guideMethod.sweepValue,
            booleanOperation: booleanOperation.sweepValue,
            keepTools: keepTools,
            simplify: simplify,
            resultKind: resultKind.sweepValue
        )
        return (
            sections: sections,
            path: path,
            guides: guides,
            targets: targets,
            options: options
        )
    }
}
