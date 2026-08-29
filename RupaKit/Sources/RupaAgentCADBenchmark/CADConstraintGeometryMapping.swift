import Foundation
import SwiftCAD

/// Maps public constraint geometry to one complete source sketch.
enum CADConstraintGeometryMapping {
    static func sketch(
        from action: CADConstraintAction,
        modelingTolerance: ModelingTolerance,
        caseID: CADBenchmarkCaseID
    ) throws -> Sketch {
        guard action.name.isEmpty == false else {
            throw invalid(caseID, "Constraint sketch name must not be empty.")
        }
        let anchor = try anchor(of: action.first, caseID: caseID)
        let sourcePlane = try CADLineGeometryMapping.sourcePlane(
            orientation: action.plane,
            anchor: anchor,
            modelingTolerance: modelingTolerance,
            caseID: caseID
        )
        let first = try mappedEntity(
            action.first,
            sourcePlane: sourcePlane,
            modelingTolerance: modelingTolerance,
            caseID: caseID,
            field: "constraint.first"
        )
        let second = try action.second.map {
            try mappedEntity(
                $0,
                sourcePlane: sourcePlane,
                modelingTolerance: modelingTolerance,
                caseID: caseID,
                field: "constraint.second"
            )
        }
        try validateShape(
            relation: action.relation,
            first: first,
            second: second,
            caseID: caseID
        )

        let firstID = SketchEntityID()
        let secondID = second.map { _ in SketchEntityID() }
        let relation = try constraint(
            relation: action.relation,
            first: first,
            firstID: firstID,
            second: second,
            secondID: secondID,
            tolerance: modelingTolerance,
            caseID: caseID
        )
        var entities = [firstID: first.entity]
        var entityOrder = [firstID]
        if let second, let secondID {
            entities[secondID] = second.entity
            entityOrder.append(secondID)
        }
        return Sketch(
            plane: sourcePlane,
            entities: entities,
            entityOrder: entityOrder,
            constraints: [relation]
        )
    }

    private struct MappedEntity {
        enum Kind {
            case line(start: Point2D, end: Point2D)
            case circle
        }

        let entity: SketchEntity
        let kind: Kind
    }

    private static func mappedEntity(
        _ geometry: CADConstraintGeometry,
        sourcePlane: SketchPlane,
        modelingTolerance: ModelingTolerance,
        caseID: CADBenchmarkCaseID,
        field: String
    ) throws -> MappedEntity {
        switch geometry {
        case let .line(start, end):
            let mappedStart = try CADLineGeometryMapping.projection(
                of: start,
                sourcePlane: sourcePlane,
                modelingTolerance: modelingTolerance,
                caseID: caseID,
                field: "\(field).start"
            ).point
            let mappedEnd = try CADLineGeometryMapping.projection(
                of: end,
                sourcePlane: sourcePlane,
                modelingTolerance: modelingTolerance,
                caseID: caseID,
                field: "\(field).end"
            ).point
            guard distance(from: mappedStart, to: mappedEnd) > modelingTolerance.distance else {
                throw invalid(caseID, "\(field) line must be non-degenerate.")
            }
            return MappedEntity(
                entity: .line(SketchLine(
                    start: sketchPoint(mappedStart),
                    end: sketchPoint(mappedEnd)
                )),
                kind: .line(start: mappedStart, end: mappedEnd)
            )
        case let .circle(center, radius):
            try radius.validate(caseID: caseID, field: "\(field).radius")
            guard radius.meters > modelingTolerance.distance else {
                throw invalid(caseID, "\(field) circle must be non-degenerate.")
            }
            let mappedCenter = try CADLineGeometryMapping.projection(
                of: center,
                sourcePlane: sourcePlane,
                modelingTolerance: modelingTolerance,
                caseID: caseID,
                field: "\(field).center"
            ).point
            return MappedEntity(
                entity: .circle(SketchCircle(
                    center: sketchPoint(mappedCenter),
                    radius: .constant(.length(radius.meters, unit: .meter))
                )),
                kind: .circle
            )
        }
    }

    private static func validateShape(
        relation: CADConstraintRelation,
        first: MappedEntity,
        second: MappedEntity?,
        caseID: CADBenchmarkCaseID
    ) throws {
        switch relation {
        case .horizontal, .vertical:
            guard case .line = first.kind, second == nil else {
                throw invalid(caseID, "Single-line relations require exactly one line.")
            }
        case .coincident, .parallel, .perpendicular, .equalLength:
            guard case .line = first.kind,
                  let second,
                  case .line = second.kind else {
                throw invalid(caseID, "Two-line relations require exactly two lines.")
            }
        case .concentric, .equalRadius:
            guard case .circle = first.kind,
                  let second,
                  case .circle = second.kind else {
                throw invalid(caseID, "Circular relations require exactly two circles.")
            }
        }
    }

    private static func constraint(
        relation: CADConstraintRelation,
        first: MappedEntity,
        firstID: SketchEntityID,
        second: MappedEntity?,
        secondID: SketchEntityID?,
        tolerance: ModelingTolerance,
        caseID: CADBenchmarkCaseID
    ) throws -> SketchConstraint {
        switch relation {
        case .horizontal:
            return .horizontal(firstID)
        case .vertical:
            return .vertical(firstID)
        case .parallel:
            return .parallel(firstID, try required(secondID, caseID: caseID))
        case .perpendicular:
            return .perpendicular(firstID, try required(secondID, caseID: caseID))
        case .equalLength:
            return .equalLength(firstID, try required(secondID, caseID: caseID))
        case .concentric:
            return .concentric(firstID, try required(secondID, caseID: caseID))
        case .equalRadius:
            return .equalRadius(firstID, try required(secondID, caseID: caseID))
        case .coincident:
            guard case let .line(firstStart, firstEnd) = first.kind,
                  let second,
                  case let .line(secondStart, secondEnd) = second.kind,
                  let secondID else {
                throw invalid(caseID, "Coincident requires two lines.")
            }
            let candidates: [(Point2D, SketchReference, Point2D, SketchReference)] = [
                (firstStart, .lineStart(firstID), secondStart, .lineStart(secondID)),
                (firstStart, .lineStart(firstID), secondEnd, .lineEnd(secondID)),
                (firstEnd, .lineEnd(firstID), secondStart, .lineStart(secondID)),
                (firstEnd, .lineEnd(firstID), secondEnd, .lineEnd(secondID)),
            ]
            let matches = candidates.filter {
                distance(from: $0.0, to: $0.2) <= tolerance.distance
            }
            guard matches.count == 1, let match = matches.first else {
                throw invalid(caseID, "Coincident input requires exactly one shared endpoint pair.")
            }
            return .coincident(match.1, match.3)
        }
    }

    private static func anchor(
        of geometry: CADConstraintGeometry,
        caseID: CADBenchmarkCaseID
    ) throws -> CADPoint3D {
        switch geometry {
        case .line(let start, _):
            try start.validate(caseID: caseID, field: "constraint.anchor")
            return start
        case .circle(let center, _):
            try center.validate(caseID: caseID, field: "constraint.anchor")
            return center
        }
    }

    private static func sketchPoint(_ point: Point2D) -> SketchPoint {
        SketchPoint(
            x: .constant(.length(point.x, unit: .meter)),
            y: .constant(.length(point.y, unit: .meter))
        )
    }

    private static func distance(from first: Point2D, to second: Point2D) -> Double {
        hypot(second.x - first.x, second.y - first.y)
    }

    private static func required(
        _ id: SketchEntityID?,
        caseID: CADBenchmarkCaseID
    ) throws -> SketchEntityID {
        guard let id else {
            throw invalid(caseID, "The relation is missing its second entity.")
        }
        return id
    }

    private static func invalid(
        _ caseID: CADBenchmarkCaseID,
        _ reason: String
    ) -> CADBenchmarkError {
        CADBenchmarkError.invalidInput(caseID: caseID.rawValue, reason: reason)
    }
}
