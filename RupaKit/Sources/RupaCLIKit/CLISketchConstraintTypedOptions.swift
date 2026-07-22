import ArgumentParser
import Foundation
import RupaCore

public struct CLISketchConstraintTypedOptions: ParsableArguments {
    @Option(help: "Typed SketchConstraint kind.")
    public var kind: CLISketchConstraintKind?

    @Option(help: "Entity ID for single-entity constraints or fixed references.")
    public var entityID: String?

    @Option(help: "First entity ID for two-entity constraints or first reference entity ID.")
    public var firstID: String?

    @Option(help: "Second entity ID for two-entity constraints or second reference entity ID.")
    public var secondID: String?

    @Option(help: "First reference kind for coincident constraints.")
    public var firstReferenceKind: CLISketchReferenceKind?

    @Option(help: "Second reference kind for coincident constraints.")
    public var secondReferenceKind: CLISketchReferenceKind?

    @Option(help: "Reference kind for fixed constraints.")
    public var referenceKind: CLISketchReferenceKind?

    @Option(parsing: .unconditional, help: "Spline control-point index for single-reference constraints.")
    public var controlPointIndex: Int?

    @Option(parsing: .unconditional, help: "First spline control-point index for coincident constraints.")
    public var firstControlPointIndex: Int?

    @Option(parsing: .unconditional, help: "Second spline control-point index for coincident constraints.")
    public var secondControlPointIndex: Int?

    @Option(help: "Spline entity ID for spline endpoint tangent constraints.")
    public var splineID: String?

    @Option(help: "Spline endpoint for spline endpoint tangent constraints.")
    public var endpoint: CLISketchSplineEndpointArgument?

    @Option(help: "Line entity ID for spline endpoint tangent constraints.")
    public var lineID: String?

    @Option(help: "First spline entity ID for endpoint-to-endpoint constraints.")
    public var firstSplineID: String?

    @Option(help: "Second spline entity ID for endpoint-to-endpoint constraints.")
    public var secondSplineID: String?

    @Option(help: "First spline endpoint for endpoint-to-endpoint constraints.")
    public var firstEndpoint: CLISketchSplineEndpointArgument?

    @Option(help: "Second spline endpoint for endpoint-to-endpoint constraints.")
    public var secondEndpoint: CLISketchSplineEndpointArgument?

    @Option(help: "Tangency payload kind for tangent constraints.")
    public var tangencyKind: CLISketchTangencyKind?

    @Option(help: "Line side for line-circular tangency constraints.")
    public var tangentSide: CLISketchTangentSide?

    @Option(help: "Contact relation for circular-circular tangency constraints.")
    public var circularContact: CLISketchCircularContact?

    @Option(help: "Directed tangent orientation for spline tangency constraints.")
    public var orientation: CLISketchTangentOrientation?

    public init() {}

    var hasInput: Bool {
        !providedFields.isEmpty
    }

    func decodedConstraint() throws -> SketchConstraint {
        guard let kind else {
            throw ValidationError("Provide --kind for typed SketchConstraint input or provide SketchConstraint JSON input.")
        }
        switch kind {
        case .coincident:
            try rejectUnexpectedFields(
                allowing: [
                    .kind,
                    .firstID,
                    .secondID,
                    .firstReferenceKind,
                    .secondReferenceKind,
                    .firstControlPointIndex,
                    .secondControlPointIndex,
                ],
                for: kind
            )
            return .coincident(
                try sketchReference(
                    kind: firstReferenceKind,
                    entityID: firstID,
                    controlPointIndex: firstControlPointIndex,
                    referenceName: "First reference"
                ),
                try sketchReference(
                    kind: secondReferenceKind,
                    entityID: secondID,
                    controlPointIndex: secondControlPointIndex,
                    referenceName: "Second reference"
                )
            )
        case .horizontal:
            try rejectUnexpectedFields(allowing: [.kind, .entityID], for: kind)
            return .horizontal(try sketchEntityID(entityID, optionName: "--entity-id"))
        case .vertical:
            try rejectUnexpectedFields(allowing: [.kind, .entityID], for: kind)
            return .vertical(try sketchEntityID(entityID, optionName: "--entity-id"))
        case .parallel:
            return try twoEntityConstraint(kind) { .parallel($0, $1) }
        case .perpendicular:
            return try twoEntityConstraint(kind) { .perpendicular($0, $1) }
        case .equalLength:
            return try twoEntityConstraint(kind) { .equalLength($0, $1) }
        case .tangent:
            guard let tangencyKind else {
                throw ValidationError("Provide --tangency-kind for tangent.")
            }
            switch tangencyKind {
            case .lineCircular:
                try rejectUnexpectedFields(
                    allowing: [.kind, .firstID, .secondID, .tangencyKind, .tangentSide],
                    for: kind
                )
                guard let tangentSide else {
                    throw ValidationError("Provide --tangent-side for lineCircular tangent.")
                }
                return .tangent(.lineCircular(
                    line: try sketchEntityID(firstID, optionName: "--first-id"),
                    circular: try sketchEntityID(secondID, optionName: "--second-id"),
                    side: tangentSide.constraintSide
                ))
            case .circularCircular:
                try rejectUnexpectedFields(
                    allowing: [.kind, .firstID, .secondID, .tangencyKind, .circularContact],
                    for: kind
                )
                guard let circularContact else {
                    throw ValidationError("Provide --circular-contact for circularCircular tangent.")
                }
                return .tangent(.circularCircular(
                    first: try sketchEntityID(firstID, optionName: "--first-id"),
                    second: try sketchEntityID(secondID, optionName: "--second-id"),
                    contact: circularContact.constraintContact
                ))
            }
        case .concentric:
            return try twoEntityConstraint(kind) { .concentric($0, $1) }
        case .equalRadius:
            return try twoEntityConstraint(kind) { .equalRadius($0, $1) }
        case .smoothSplineControlPoint:
            try rejectUnexpectedFields(allowing: [.kind, .entityID, .controlPointIndex], for: kind)
            guard let controlPointIndex else {
                throw ValidationError("Provide --control-point-index for smoothSplineControlPoint.")
            }
            return .smoothSplineControlPoint(
                entity: try sketchEntityID(entityID, optionName: "--entity-id"),
                index: controlPointIndex
            )
        case .splineEndpointTangent:
            try rejectUnexpectedFields(
                allowing: [.kind, .splineID, .endpoint, .lineID, .orientation],
                for: kind
            )
            guard let endpoint else {
                throw ValidationError("Provide --endpoint for splineEndpointTangent.")
            }
            guard let orientation else {
                throw ValidationError("Provide --orientation for splineEndpointTangent.")
            }
            return .splineEndpointTangent(SketchSplineLineTangencyConstraint(
                splineEndpoint: SketchSplineEndpointReference(
                    splineID: try sketchEntityID(splineID, optionName: "--spline-id"),
                    endpoint: endpoint.endpoint
                ),
                line: try sketchEntityID(lineID, optionName: "--line-id"),
                orientation: orientation.constraintOrientation
            ))
        case .tangentSplineEndpoints:
            return try twoEndpointConstraint(kind) {
                .tangentSplineEndpoints($0)
            }
        case .smoothSplineEndpoints:
            return try twoEndpointConstraint(kind) {
                .smoothSplineEndpoints($0)
            }
        case .fixed:
            try rejectUnexpectedFields(allowing: [.kind, .entityID, .referenceKind, .controlPointIndex], for: kind)
            return .fixed(
                try sketchReference(
                    kind: referenceKind,
                    entityID: entityID,
                    controlPointIndex: controlPointIndex,
                    referenceName: "Fixed reference"
                )
            )
        }
    }

    private enum Field: String, CaseIterable {
        case kind = "--kind"
        case entityID = "--entity-id"
        case firstID = "--first-id"
        case secondID = "--second-id"
        case firstReferenceKind = "--first-reference-kind"
        case secondReferenceKind = "--second-reference-kind"
        case referenceKind = "--reference-kind"
        case controlPointIndex = "--control-point-index"
        case firstControlPointIndex = "--first-control-point-index"
        case secondControlPointIndex = "--second-control-point-index"
        case splineID = "--spline-id"
        case endpoint = "--endpoint"
        case lineID = "--line-id"
        case firstSplineID = "--first-spline-id"
        case secondSplineID = "--second-spline-id"
        case firstEndpoint = "--first-endpoint"
        case secondEndpoint = "--second-endpoint"
        case tangencyKind = "--tangency-kind"
        case tangentSide = "--tangent-side"
        case circularContact = "--circular-contact"
        case orientation = "--orientation"
    }

    private var providedFields: Set<Field> {
        var fields: Set<Field> = []
        if kind != nil { fields.insert(.kind) }
        if entityID != nil { fields.insert(.entityID) }
        if firstID != nil { fields.insert(.firstID) }
        if secondID != nil { fields.insert(.secondID) }
        if firstReferenceKind != nil { fields.insert(.firstReferenceKind) }
        if secondReferenceKind != nil { fields.insert(.secondReferenceKind) }
        if referenceKind != nil { fields.insert(.referenceKind) }
        if controlPointIndex != nil { fields.insert(.controlPointIndex) }
        if firstControlPointIndex != nil { fields.insert(.firstControlPointIndex) }
        if secondControlPointIndex != nil { fields.insert(.secondControlPointIndex) }
        if splineID != nil { fields.insert(.splineID) }
        if endpoint != nil { fields.insert(.endpoint) }
        if lineID != nil { fields.insert(.lineID) }
        if firstSplineID != nil { fields.insert(.firstSplineID) }
        if secondSplineID != nil { fields.insert(.secondSplineID) }
        if firstEndpoint != nil { fields.insert(.firstEndpoint) }
        if secondEndpoint != nil { fields.insert(.secondEndpoint) }
        if tangencyKind != nil { fields.insert(.tangencyKind) }
        if tangentSide != nil { fields.insert(.tangentSide) }
        if circularContact != nil { fields.insert(.circularContact) }
        if orientation != nil { fields.insert(.orientation) }
        return fields
    }

    private func twoEntityConstraint(
        _ kind: CLISketchConstraintKind,
        build: (SketchEntityID, SketchEntityID) -> SketchConstraint
    ) throws -> SketchConstraint {
        try rejectUnexpectedFields(allowing: [.kind, .firstID, .secondID], for: kind)
        return build(
            try sketchEntityID(firstID, optionName: "--first-id"),
            try sketchEntityID(secondID, optionName: "--second-id")
        )
    }

    private func twoEndpointConstraint(
        _ kind: CLISketchConstraintKind,
        build: (SketchSplineEndpointTangencyConstraint) -> SketchConstraint
    ) throws -> SketchConstraint {
        try rejectUnexpectedFields(
            allowing: [
                .kind,
                .firstSplineID,
                .firstEndpoint,
                .secondSplineID,
                .secondEndpoint,
                .orientation,
            ],
            for: kind
        )
        guard let firstEndpoint else {
            throw ValidationError("Provide --first-endpoint for \(kind.rawValue).")
        }
        guard let secondEndpoint else {
            throw ValidationError("Provide --second-endpoint for \(kind.rawValue).")
        }
        guard let orientation else {
            throw ValidationError("Provide --orientation for \(kind.rawValue).")
        }
        return build(SketchSplineEndpointTangencyConstraint(
            first: SketchSplineEndpointReference(
                splineID: try sketchEntityID(firstSplineID, optionName: "--first-spline-id"),
                endpoint: firstEndpoint.endpoint
            ),
            second: SketchSplineEndpointReference(
                splineID: try sketchEntityID(secondSplineID, optionName: "--second-spline-id"),
                endpoint: secondEndpoint.endpoint
            ),
            orientation: orientation.constraintOrientation
        ))
    }

    private func rejectUnexpectedFields(
        allowing allowed: Set<Field>,
        for kind: CLISketchConstraintKind
    ) throws {
        let unexpected = providedFields.subtracting(allowed)
        guard unexpected.isEmpty else {
            let names = unexpected
                .map(\.rawValue)
                .sorted()
                .joined(separator: ", ")
            throw ValidationError("Unexpected typed SketchConstraint option(s) for \(kind.rawValue): \(names).")
        }
    }

    private func sketchReference(
        kind: CLISketchReferenceKind?,
        entityID value: String?,
        controlPointIndex: Int?,
        referenceName: String
    ) throws -> SketchReference {
        guard let kind else {
            throw ValidationError("Provide reference kind for \(referenceName).")
        }
        let entityID = try sketchEntityID(value, optionName: "\(referenceName) entity ID")
        switch kind {
        case .entity:
            try rejectControlPointIndex(controlPointIndex, referenceName: referenceName)
            return .entity(entityID)
        case .lineStart:
            try rejectControlPointIndex(controlPointIndex, referenceName: referenceName)
            return .lineStart(entityID)
        case .lineEnd:
            try rejectControlPointIndex(controlPointIndex, referenceName: referenceName)
            return .lineEnd(entityID)
        case .circleCenter:
            try rejectControlPointIndex(controlPointIndex, referenceName: referenceName)
            return .circleCenter(entityID)
        case .circleRadius:
            try rejectControlPointIndex(controlPointIndex, referenceName: referenceName)
            return .circleRadius(entityID)
        case .arcCenter:
            try rejectControlPointIndex(controlPointIndex, referenceName: referenceName)
            return .arcCenter(entityID)
        case .arcStart:
            try rejectControlPointIndex(controlPointIndex, referenceName: referenceName)
            return .arcStart(entityID)
        case .arcEnd:
            try rejectControlPointIndex(controlPointIndex, referenceName: referenceName)
            return .arcEnd(entityID)
        case .arcRadius:
            try rejectControlPointIndex(controlPointIndex, referenceName: referenceName)
            return .arcRadius(entityID)
        case .splineControlPoint:
            guard let controlPointIndex else {
                throw ValidationError("Provide control-point index for \(referenceName).")
            }
            return .splineControlPoint(entity: entityID, index: controlPointIndex)
        }
    }

    private func sketchEntityID(_ value: String?, optionName: String) throws -> SketchEntityID {
        guard let value else {
            throw ValidationError("Provide \(optionName).")
        }
        guard let uuid = UUID(uuidString: value) else {
            throw ValidationError("\(optionName) must be a UUID.")
        }
        return SketchEntityID(uuid)
    }

    private func rejectControlPointIndex(_ index: Int?, referenceName: String) throws {
        guard index == nil else {
            throw ValidationError("Control-point index is only valid for splineControlPoint references in \(referenceName).")
        }
    }
}
