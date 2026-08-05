import SwiftCAD

extension DesignDocument {
    private func lineEndpoint(for reference: SketchReference) -> LineEndpoint? {
        switch reference {
        case .lineStart(let entityID):
            LineEndpoint(entityID: entityID, isStart: true)
        case .lineEnd(let entityID):
            LineEndpoint(entityID: entityID, isStart: false)
        case .entity,
             .circleCenter,
             .circleRadius,
             .arcCenter,
             .arcStart,
             .arcEnd,
             .arcRadius,
             .splineControlPoint:
            nil
        }
    }

    private func arcEndpoint(for reference: SketchReference) -> ArcEndpoint? {
        switch reference {
        case .arcStart(let entityID):
            ArcEndpoint(entityID: entityID, isStart: true)
        case .arcEnd(let entityID):
            ArcEndpoint(entityID: entityID, isStart: false)
        case .entity,
             .lineStart,
             .lineEnd,
             .circleCenter,
             .circleRadius,
             .arcCenter,
             .arcRadius,
             .splineControlPoint:
            nil
        }
    }

    func sketchCurveEndpoint(for reference: SketchReference) -> SketchCurveEndpoint? {
        if let lineEndpoint = lineEndpoint(for: reference) {
            return .line(lineEndpoint)
        }
        if let arcEndpoint = arcEndpoint(for: reference) {
            return .arc(arcEndpoint)
        }
        return nil
    }

    func dimensionReferencesAny(
        _ dimension: SketchDimension,
        entityIDs: Set<SketchEntityID>
    ) -> Bool {
        switch dimension {
        case .distance(let first, let second, _),
             .angle(let first, let second, _):
            entityIDs.contains(entityID(for: first)) || entityIDs.contains(entityID(for: second))
        case .radius(let entityID, _),
             .diameter(let entityID, _):
            entityIDs.contains(entityID)
        }
    }

    func constraintReferencesAny(
        _ constraint: SketchConstraint,
        entityIDs: Set<SketchEntityID>
    ) -> Bool {
        switch constraint {
        case .coincident(let first, let second):
            return entityIDs.contains(entityID(for: first)) || entityIDs.contains(entityID(for: second))
        case .horizontal(let entityID),
             .vertical(let entityID),
             .smoothSplineControlPoint(let entityID, _):
            return entityIDs.contains(entityID)
        case .parallel(let first, let second),
             .perpendicular(let first, let second),
             .equalLength(let first, let second),
             .concentric(let first, let second),
             .equalRadius(let first, let second):
            return entityIDs.contains(first) || entityIDs.contains(second)
        case .tangent(let tangency):
            switch tangency {
            case .lineCircular(let line, let circular, _):
                return entityIDs.contains(line) || entityIDs.contains(circular)
            case .circularCircular(let first, let second, _):
                return entityIDs.contains(first) || entityIDs.contains(second)
            }
        case .splineEndpointTangent(let constraint):
            return entityIDs.contains(constraint.splineEndpoint.splineID) ||
                entityIDs.contains(constraint.line)
        case .tangentSplineEndpoints(let constraint),
             .smoothSplineEndpoints(let constraint):
            return entityIDs.contains(constraint.first.splineID) ||
                entityIDs.contains(constraint.second.splineID)
        case .fixed(let reference):
            return entityIDs.contains(entityID(for: reference))
        }
    }

    func entityID(for reference: SketchReference) -> SketchEntityID {
        switch reference {
        case .entity(let entityID),
             .lineStart(let entityID),
             .lineEnd(let entityID),
             .circleCenter(let entityID),
             .circleRadius(let entityID),
             .arcCenter(let entityID),
             .arcStart(let entityID),
             .arcEnd(let entityID),
             .arcRadius(let entityID),
             .splineControlPoint(let entityID, _):
            entityID
        }
    }

    func sketchConstraint(
        _ constraint: SketchConstraint,
        references entityID: SketchEntityID
    ) -> Bool {
        switch constraint {
        case .coincident(let first, let second):
            return sketchReference(first, references: entityID) ||
                sketchReference(second, references: entityID)
        case .fixed(let reference):
            return sketchReference(reference, references: entityID)
        case .horizontal(let id),
             .vertical(let id),
             .smoothSplineControlPoint(let id, _):
            return id == entityID
        case .parallel(let first, let second),
             .perpendicular(let first, let second),
             .equalLength(let first, let second),
             .concentric(let first, let second),
             .equalRadius(let first, let second):
            return first == entityID || second == entityID
        case .tangent(let tangency):
            switch tangency {
            case .lineCircular(let line, let circular, _):
                return line == entityID || circular == entityID
            case .circularCircular(let first, let second, _):
                return first == entityID || second == entityID
            }
        case .splineEndpointTangent(let constraint):
            return constraint.splineEndpoint.splineID == entityID || constraint.line == entityID
        case .tangentSplineEndpoints(let constraint),
             .smoothSplineEndpoints(let constraint):
            return constraint.first.splineID == entityID || constraint.second.splineID == entityID
        }
    }

    func sketchDimension(
        _ dimension: SketchDimension,
        references entityID: SketchEntityID
    ) -> Bool {
        switch dimension {
        case .distance(let from, let to, _),
             .angle(let from, let to, _):
            return sketchReference(from, references: entityID) ||
                sketchReference(to, references: entityID)
        case .radius(let id, _),
             .diameter(let id, _):
            return id == entityID
        }
    }

    func sketchReference(
        _ reference: SketchReference,
        references entityID: SketchEntityID
    ) -> Bool {
        switch reference {
        case .entity(let id),
             .lineStart(let id),
             .lineEnd(let id),
             .circleCenter(let id),
             .circleRadius(let id),
             .arcCenter(let id),
             .arcStart(let id),
             .arcEnd(let id),
             .arcRadius(let id),
             .splineControlPoint(let id, _):
            return id == entityID
        }
    }
}
