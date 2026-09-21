import Foundation
import RupaCore
import RupaKit
import SwiftCAD

enum CADConstraintOracleError: Error, Equatable, CustomStringConvertible {
    case mismatch(String)

    var description: String {
        switch self {
        case .mismatch(let reason):
            "Constraint oracle mismatch: \(reason)"
        }
    }
}

struct CADConstraintOracleObservation: Equatable, Sendable {
    let readCount: Int
    let entityCount: Int
    let featureCount: Int
    let bodyCount: Int
}

/// Exact source observation for an activated sketch-relation case.
enum CADConstraintOracle {
    static func evaluate(
        expected: CADConstraintChallengeInput,
        challenge: CADChallenge,
        bindings: CADOutputRoleBindings,
        stepResults: [CADCandidateStepResult],
        snapshot: ProjectViewSnapshot
    ) throws -> CADConstraintOracleObservation {
        let caseID = challenge.id
        guard CADActivatedConstraintCase(rawValue: caseID.rawValue) != nil,
              challenge.category == .constraint else {
            throw mismatch("The oracle received an inactive or non-constraint challenge.")
        }
        try expected.validate(caseID: caseID)
        let projection: CADConstraintChallengeProjection
        do {
            projection = try CADConstraintChallengeProjection.decode(challenge)
        } catch {
            throw mismatch("The candidate-visible constraint challenge could not be decoded: \(error).")
        }
        guard projectionMatches(projection, expected: expected) else {
            throw mismatch("The candidate-visible challenge and private constraint expectation disagree.")
        }
        try bindings.validate(for: challenge, availableStepResults: stepResults)
        guard bindings.bindings.count == 1,
              let binding = bindings.bindings.first,
              binding.role == "relation",
              let step = stepResults.first(where: { $0.stepIndex == binding.stepIndex }) else {
            throw mismatch("The relation role is not bound to one candidate step.")
        }
        let featureDescription = try binding.selector.resolveFeatureID(
            from: step,
            caseID: caseID,
            role: binding.role
        )
        guard let featureUUID = UUID(uuidString: featureDescription) else {
            throw mismatch("The bound FeatureID is not a tagged UUID.")
        }
        let featureID = FeatureID(featureUUID)
        let document = snapshot.document.document
        let graph = document.cadDocument.designGraph
        guard graph.order == [featureID],
              graph.nodes.count == 1,
              let feature = graph.nodes[featureID],
              feature.isSuppressed == false,
              feature.outputs.contains(where: { $0.role == .curve }),
              case .sketch(let sketch) = feature.operation else {
            throw mismatch("The bound feature is not the sole unsuppressed curve sketch.")
        }
        let tolerance = try CADBenchmarkTolerancePolicy(
            modelingTolerance: document.modelingSettings.tolerance
        )
        let expectedPlane = try sourcePlane(
            expected: expected,
            tolerance: tolerance.modelingTolerance,
            caseID: caseID
        )
        let expectedCount = expected.second == nil ? 1 : 2
        guard sketch.plane == expectedPlane,
              sketch.entities.count == expectedCount,
              sketch.entityOrder.count == expectedCount,
              sketch.orderedEntities.map(\.id) == sketch.entityOrder,
              sketch.constraints.count == 1,
              sketch.dimensions.isEmpty else {
            throw mismatch("The source sketch shape, order, relation, or dimension count is wrong.")
        }
        let ordered = sketch.orderedEntities
        try validateEntity(
            ordered[0].entity,
            expected: expected.first,
            plane: expectedPlane,
            tolerance: tolerance,
            caseID: caseID
        )
        if let expectedSecond = expected.second {
            try validateEntity(
                ordered[1].entity,
                expected: expectedSecond,
                plane: expectedPlane,
                tolerance: tolerance,
                caseID: caseID
            )
        }
        let expectedConstraint = try sourceConstraint(
            expected: expected,
            firstID: ordered[0].id,
            secondID: ordered.count == 2 ? ordered[1].id : nil,
            caseID: caseID
        )
        guard sketch.constraints == [expectedConstraint] else {
            throw mismatch("The source relation kind or entity references are wrong.")
        }

        let source: SketchEntitySnapshot
        do {
            source = try SketchEntitySnapshotService().snapshot(
                document: document,
                objectRegistry: snapshot.objectRegistry
            )
        } catch {
            throw mismatch("The immutable source snapshot could not be read: \(error).")
        }
        guard source.counts.sketchCount == 1,
              source.counts.entityCount == expectedCount,
              source.counts.constraintCount == 1,
              source.counts.dimensionCount == 0,
              source.sketches.count == 1,
              let sketchEntry = source.sketches.first,
              sketchEntry.sourceFeatureID == featureDescription,
              sketchEntry.plane == expectedPlane,
              sketchEntry.entityCount == expectedCount,
              sketchEntry.constraintCount == 1,
              sketchEntry.dimensionCount == 0,
              source.entries.allSatisfy({
                  $0.sourceFeatureID == featureDescription && $0.dimensions.isEmpty
              }) else {
            throw mismatch("The immutable source snapshot contains extra or missing source state.")
        }
        let expectedEntry = constraintEntry(expectedConstraint)
        let affectedEntries = source.entries.filter { $0.constraints.contains(expectedEntry) }
        let expectedAffectedCount = expected.second == nil ? 1 : 2
        guard affectedEntries.count == expectedAffectedCount else {
            throw mismatch("The immutable relation references do not match the source relation.")
        }
        try CADConstraintDerivedRegionOracle.validate(
            source: source,
            expected: expected,
            expectedPlane: expectedPlane,
            sourceFeatureID: featureDescription,
            sceneNodeID: sketchEntry.sceneNodeID,
            tolerance: tolerance
        )
        guard snapshot.evaluationSnapshot.bodyCount == 0 else {
            throw mismatch("A constraint case must leave zero evaluated bodies.")
        }
        return CADConstraintOracleObservation(
            readCount: 1,
            entityCount: source.counts.entityCount,
            featureCount: graph.nodes.count,
            bodyCount: snapshot.evaluationSnapshot.bodyCount
        )
    }

    private static func projectionMatches(
        _ projection: CADConstraintChallengeProjection,
        expected: CADConstraintChallengeInput
    ) -> Bool {
        projection.relation.rawValue == expected.relation.rawValue
            && geometryMatches(projection.first, expected: expected.first)
            && optionalGeometryMatches(projection.second, expected: expected.second)
    }

    private static func optionalGeometryMatches(
        _ publicGeometry: CADConstraintGeometry?,
        expected: CADConstraintGeometryInput?
    ) -> Bool {
        switch (publicGeometry, expected) {
        case (nil, nil): true
        case let (publicGeometry?, expected?): geometryMatches(publicGeometry, expected: expected)
        default: false
        }
    }

    private static func geometryMatches(
        _ publicGeometry: CADConstraintGeometry,
        expected: CADConstraintGeometryInput
    ) -> Bool {
        switch (publicGeometry, expected) {
        case let (.line(start, end), .line(line)):
            return start.meters == line.start.meters
                && end.meters == line.end.meters
                && line.plane == .xy
        case let (.circle(center, radius), .circle(circle)):
            return center.meters == circle.center.meters
                && radius.meters == circle.radius.meters
                && circle.plane == .xy
        default:
            return false
        }
    }

    private static func sourcePlane(
        expected: CADConstraintChallengeInput,
        tolerance: ModelingTolerance,
        caseID: CADBenchmarkCaseID
    ) throws -> SketchPlane {
        let (plane, anchor): (CADSketchPlane, CADPoint3D)
        switch expected.first {
        case .line(let line):
            (plane, anchor) = (line.plane, line.start)
        case .circle(let circle):
            (plane, anchor) = (circle.plane, circle.center)
        }
        return try CADLineGeometryMapping.sourcePlane(
            orientation: plane,
            anchor: anchor,
            modelingTolerance: tolerance,
            caseID: caseID
        )
    }

    private static func validateEntity(
        _ entity: SketchEntity,
        expected: CADConstraintGeometryInput,
        plane: SketchPlane,
        tolerance: CADBenchmarkTolerancePolicy,
        caseID: CADBenchmarkCaseID
    ) throws {
        switch (entity, expected) {
        case let (.line(line), .line(input)):
            let document = try expressionDocument(for: line, plane: plane)
            let source = try SketchEntitySnapshotService().snapshot(document: document)
            guard let entry = source.entries.first,
                  let start = entry.start,
                  let end = entry.end else {
                throw mismatch("A source line has no resolved endpoints.")
            }
            let startWorld = try CADLineGeometryMapping.worldPoint(
                from: start,
                sourcePlane: plane,
                modelingTolerance: tolerance.modelingTolerance
            )
            let endWorld = try CADLineGeometryMapping.worldPoint(
                from: end,
                sourcePlane: plane,
                modelingTolerance: tolerance.modelingTolerance
            )
            guard accepts(input.start, startWorld, tolerance),
                  accepts(input.end, endWorld, tolerance) else {
                throw mismatch("A source line has incorrect oriented world endpoints.")
            }
        case let (.circle(circle), .circle(input)):
            let document = try expressionDocument(for: circle, plane: plane)
            let source = try SketchEntitySnapshotService().snapshot(document: document)
            guard let entry = source.entries.first,
                  let center = entry.center,
                  let radius = entry.radius else {
                throw mismatch("A source circle has no resolved center or radius.")
            }
            let centerWorld = try CADLineGeometryMapping.worldPoint(
                from: center,
                sourcePlane: plane,
                modelingTolerance: tolerance.modelingTolerance
            )
            guard accepts(input.center, centerWorld, tolerance),
                  tolerance.acceptsLinear(expected: input.radius.meters, observed: radius) else {
                throw mismatch("A source circle has incorrect world center or radius.")
            }
        default:
            throw mismatch("A source entity kind does not match the expected geometry.")
        }
        _ = caseID
    }

    private static func expressionDocument(
        for line: SketchLine,
        plane: SketchPlane
    ) throws -> DesignDocument {
        var document = DesignDocument.empty()
        let id = SketchEntityID()
        _ = try document.createSketch(
            name: "Constraint Oracle Line",
            sketch: Sketch(
                plane: plane,
                entities: [id: .line(line)],
                entityOrder: [id]
            ),
            geometryRole: .curve
        )
        return document
    }

    private static func expressionDocument(
        for circle: SketchCircle,
        plane: SketchPlane
    ) throws -> DesignDocument {
        var document = DesignDocument.empty()
        let id = SketchEntityID()
        _ = try document.createSketch(
            name: "Constraint Oracle Circle",
            sketch: Sketch(
                plane: plane,
                entities: [id: .circle(circle)],
                entityOrder: [id]
            ),
            geometryRole: .curve
        )
        return document
    }

    private static func sourceConstraint(
        expected: CADConstraintChallengeInput,
        firstID: SketchEntityID,
        secondID: SketchEntityID?,
        caseID: CADBenchmarkCaseID
    ) throws -> SketchConstraint {
        switch expected.relation {
        case .horizontal: return .horizontal(firstID)
        case .vertical: return .vertical(firstID)
        case .parallel: return .parallel(firstID, try required(secondID, caseID))
        case .perpendicular: return .perpendicular(firstID, try required(secondID, caseID))
        case .equalLength: return .equalLength(firstID, try required(secondID, caseID))
        case .concentric: return .concentric(firstID, try required(secondID, caseID))
        case .equalRadius: return .equalRadius(firstID, try required(secondID, caseID))
        case .coincident:
            guard case let .line(first) = expected.first,
                  let secondGeometry = expected.second,
                  case let .line(second) = secondGeometry,
                  let secondID else {
                throw mismatch("Coincident expectation requires two lines.")
            }
            let pairs: [(CADPoint3D, SketchReference, CADPoint3D, SketchReference)] = [
                (first.start, .lineStart(firstID), second.start, .lineStart(secondID)),
                (first.start, .lineStart(firstID), second.end, .lineEnd(secondID)),
                (first.end, .lineEnd(firstID), second.start, .lineStart(secondID)),
                (first.end, .lineEnd(firstID), second.end, .lineEnd(secondID)),
            ]
            let matches = pairs.filter { $0.0.meters == $0.2.meters }
            guard matches.count == 1, let match = matches.first else {
                throw mismatch("Coincident expectation has no unique shared endpoint.")
            }
            return .coincident(match.1, match.3)
        }
    }

    private static func required(
        _ id: SketchEntityID?,
        _ caseID: CADBenchmarkCaseID
    ) throws -> SketchEntityID {
        guard let id else {
            throw mismatch("\(caseID.rawValue) is missing a second source entity.")
        }
        return id
    }

    private static func constraintEntry(
        _ constraint: SketchConstraint
    ) -> SketchEntitySummaryResult.ConstraintEntry {
        switch constraint {
        case .coincident(let first, let second):
            return .init(kind: "coincident", references: [reference(first), reference(second)])
        case .horizontal(let id): return .init(kind: "horizontal", references: [entity(id)])
        case .vertical(let id): return .init(kind: "vertical", references: [entity(id)])
        case .parallel(let first, let second): return .init(kind: "parallel", references: [entity(first), entity(second)])
        case .perpendicular(let first, let second): return .init(kind: "perpendicular", references: [entity(first), entity(second)])
        case .equalLength(let first, let second): return .init(kind: "equalLength", references: [entity(first), entity(second)])
        case .concentric(let first, let second): return .init(kind: "concentric", references: [entity(first), entity(second)])
        case .equalRadius(let first, let second): return .init(kind: "equalRadius", references: [entity(first), entity(second)])
        default: return .init(kind: "unsupported", references: [])
        }
    }

    private static func reference(_ value: SketchReference) -> String {
        switch value {
        case .entity(let id): entity(id)
        case .lineStart(let id): "lineStart:\(id.description)"
        case .lineEnd(let id): "lineEnd:\(id.description)"
        case .circleCenter(let id): "circleCenter:\(id.description)"
        case .circleRadius(let id): "circleRadius:\(id.description)"
        case .arcCenter(let id): "arcCenter:\(id.description)"
        case .arcStart(let id): "arcStart:\(id.description)"
        case .arcEnd(let id): "arcEnd:\(id.description)"
        case .arcRadius(let id): "arcRadius:\(id.description)"
        case .splineControlPoint(let id, let index): "splineControlPoint:\(id.description):\(index)"
        }
    }

    private static func entity(_ id: SketchEntityID) -> String {
        "entity:\(id.description)"
    }

    private static func accepts(
        _ expected: CADPoint3D,
        _ observed: Point3D,
        _ tolerance: CADBenchmarkTolerancePolicy
    ) -> Bool {
        let meters = expected.meters
        return tolerance.acceptsLinear(expected: meters.x, observed: observed.x)
            && tolerance.acceptsLinear(expected: meters.y, observed: observed.y)
            && tolerance.acceptsLinear(expected: meters.z, observed: observed.z)
    }

    private static func mismatch(_ reason: String) -> CADConstraintOracleError {
        .mismatch(reason)
    }
}
