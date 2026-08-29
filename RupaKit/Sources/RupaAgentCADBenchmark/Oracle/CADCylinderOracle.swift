import Foundation
import RupaCore
import RupaKit
import SwiftCAD

enum CADCylinderOracleError: Error, Equatable, CustomStringConvertible {
    case mismatch(String)

    var description: String {
        switch self {
        case .mismatch(let reason):
            "Cylinder oracle mismatch: \(reason)"
        }
    }
}

struct CADCylinderOracleObservation: Equatable, Sendable {
    let readCount: Int
    let entityCount: Int
    let featureCount: Int
    let bodyCount: Int
    let faceCount: Int
    let edgeCount: Int
    let vertexCount: Int
    let volumeCubicMeters: Double
}

/// Exact source and B-rep observation for an activated analytic-cylinder case.
enum CADCylinderOracle {
    static func evaluate(
        expected: CADCylinderChallengeInput,
        challenge: CADChallenge,
        bindings: CADOutputRoleBindings,
        stepResults: [CADCandidateStepResult],
        snapshot: ProjectViewSnapshot
    ) throws -> CADCylinderOracleObservation {
        let caseID = challenge.id
        guard CADActivatedCylinderCase(rawValue: caseID.rawValue) != nil,
              challenge.category == .cylinder else {
            throw CADCylinderOracleError.mismatch(
                "The oracle received an inactive or non-cylinder challenge."
            )
        }
        try CADChallengeGeometryValidator.validate(.cylinder(expected), caseID: caseID)
        let projection: CADCylinderChallengeProjection
        do {
            projection = try CADCylinderChallengeProjection.decode(challenge)
        } catch {
            throw CADCylinderOracleError.mismatch(
                "The candidate-visible cylinder challenge could not be decoded: \(error)."
            )
        }
        guard projection.baseCenter.meters == expected.baseCenter.meters,
              projection.axis == expected.axis,
              projection.radius.meters == expected.radius.meters,
              projection.depth.meters == expected.depth.meters else {
            throw CADCylinderOracleError.mismatch(
                "The candidate-visible challenge and private cylinder expectation disagree."
            )
        }

        do {
            try bindings.validate(for: challenge, availableStepResults: stepResults)
        } catch {
            throw CADCylinderOracleError.mismatch(
                "The output role bindings are invalid: \(error)."
            )
        }
        guard bindings.bindings.count == 1,
              let binding = bindings.bindings.first,
              binding.role == "solid",
              let stepResult = stepResults.first(where: { $0.stepIndex == binding.stepIndex }) else {
            throw CADCylinderOracleError.mismatch(
                "The solid role is not bound to one candidate step."
            )
        }
        let featureIDDescription: String
        do {
            featureIDDescription = try binding.selector.resolveFeatureID(
                from: stepResult,
                caseID: caseID,
                role: binding.role
            )
        } catch {
            throw CADCylinderOracleError.mismatch(
                "The solid role could not resolve its body feature."
            )
        }
        guard let featureUUID = UUID(uuidString: featureIDDescription) else {
            throw CADCylinderOracleError.mismatch(
                "The bound body FeatureID is not a tagged UUID."
            )
        }

        let bodyFeatureID = FeatureID(featureUUID)
        let document = snapshot.document.document
        let graph = document.cadDocument.designGraph
        let tolerance = try CADBenchmarkTolerancePolicy(
            modelingTolerance: document.modelingSettings.tolerance
        )
        let sourceGeometry: CADCylinderGeometryMapping.CommandGeometry
        do {
            sourceGeometry = try CADCylinderGeometryMapping.commandGeometry(
                baseCenter: expected.baseCenter,
                axis: expected.axis,
                caseID: caseID
            )
        } catch {
            throw CADCylinderOracleError.mismatch(
                "The expected cylinder source plane could not be constructed: \(error)."
            )
        }

        guard graph.order.count == 2,
              graph.nodes.count == 2,
              graph.nodes.values.filter({ !$0.isSuppressed }).count == 2,
              graph.order.last == bodyFeatureID,
              let sketchFeatureID = graph.order.first,
              let sketchFeature = graph.nodes[sketchFeatureID],
              let bodyFeature = graph.nodes[bodyFeatureID],
              sketchFeature.outputs.contains(where: { $0.role == .profile }),
              bodyFeature.outputs.contains(where: { $0.role == .body }),
              case .sketch(let sketch) = sketchFeature.operation,
              sketch.plane == sourceGeometry.plane,
              sketch.entities.count == 1,
              sketch.entities.values.contains(where: {
                  if case .circle = $0 { return true }
                  return false
              }),
              case .extrude(let extrude) = bodyFeature.operation,
              extrude.profile.featureID == sketchFeatureID,
              extrude.profile.profileIndex == 0,
              extrude.direction == .normal,
              extrude.operation == .newBody else {
            throw CADCylinderOracleError.mismatch(
                "The cylinder source must be one analytic-circle sketch followed by one normal extrude."
            )
        }
        guard let bodyNode = document.productMetadata.sceneNodes.values.first(where: {
            $0.reference == .body(bodyFeatureID)
        }),
        let bodyObject = bodyNode.object,
        bodyObject.category == .body,
        bodyObject.geometryRole == .solid,
        bodyObject.typeID == .cylinder else {
            throw CADCylinderOracleError.mismatch(
                "The primary body is not represented as a cylinder solid."
            )
        }
        let depthQuantity = try document.cadDocument.parameters.resolvedValue(for: extrude.distance)
        guard depthQuantity.kind == .length,
              tolerance.acceptsLinear(
                  expected: expected.depth.meters,
                  observed: depthQuantity.value
              ) else {
            throw CADCylinderOracleError.mismatch(
                "The extrude depth does not match cylinder depth."
            )
        }

        let source: SketchEntitySnapshot
        do {
            source = try SketchEntitySnapshotService().snapshot(
                document: document,
                objectRegistry: snapshot.objectRegistry
            )
        } catch {
            throw CADCylinderOracleError.mismatch(
                "The immutable cylinder source snapshot could not be read: \(error)."
            )
        }
        guard source.counts.sketchCount == 1,
              source.counts.entityCount == 1,
              source.counts.regionCount == 1,
              source.entries.count == 1,
              source.sketches.count == 1,
              source.regions.count == 1,
              let entity = source.entries.first,
              let sketchEntry = source.sketches.first,
              let region = source.regions.first,
              entity.sourceFeatureID == sketchFeatureID.description,
              entity.entityKind == "circle",
              entity.center != nil,
              entity.radius != nil,
              sketchEntry.sourceFeatureID == sketchFeatureID.description,
              sketchEntry.plane == sourceGeometry.plane,
              sketchEntry.entityCount == 1,
              region.sourceFeatureID == sketchFeatureID.description,
              region.plane == sourceGeometry.plane,
              region.boundarySegmentCount == 1,
              let localCenter = entity.center,
              let sourceRadius = entity.radius,
              tolerance.acceptsLinear(expected: 0, observed: localCenter.x),
              tolerance.acceptsLinear(expected: 0, observed: localCenter.y),
              tolerance.acceptsLinear(expected: expected.radius.meters, observed: sourceRadius),
              tolerance.acceptsLinear(expected: 0, observed: region.center.x),
              tolerance.acceptsLinear(expected: 0, observed: region.center.y),
              acceptsArea(
                  expected: Double.pi * expected.radius.meters * expected.radius.meters,
                  observed: region.areaSquareMeters,
                  radius: expected.radius.meters,
                  tolerance: tolerance.modelingTolerance
              ) else {
            throw CADCylinderOracleError.mismatch(
                "The source snapshot is not one exact analytic circular profile at the base center."
            )
        }

        guard let evaluation = snapshot.cadInteraction else {
            throw CADCylinderOracleError.mismatch(
                "The final view has no immutable CAD evaluation."
            )
        }
        let topology: TopologySnapshot
        do {
            topology = try TopologySnapshotService().snapshot(
                document: document,
                objectRegistry: snapshot.objectRegistry,
                currentEvaluation: evaluation,
                currentGeneration: snapshot.documentGeneration
            )
        } catch {
            throw CADCylinderOracleError.mismatch(
                "The immutable evaluated B-rep could not be read: \(error)."
            )
        }
        guard topology.counts.bodyCount == 1,
              topology.counts.faceCount == 6,
              topology.counts.edgeCount == 12,
              topology.counts.vertexCount == 8 else {
            throw CADCylinderOracleError.mismatch(
                "The evaluated cylinder topology must contain 1 body, 6 faces, 12 edges, and 8 vertices."
            )
        }
        let entries = topology.entries.filter { $0.sourceFeatureID == bodyFeatureID.description }
        let cylinderFaces = entries.filter { $0.kind == .face && $0.surfaceKind == "cylinder" }
        let planarFaces = entries.filter { $0.kind == .face && $0.surfaceKind == "plane" }
        let circularEdges = entries.filter { $0.kind == .edge && $0.curveKind == "circle" }
        let seamEdges = entries.filter { $0.kind == .edge && $0.curveKind == "line" }
        let base = expected.baseCenter.meters
        let axis = sourceGeometry.normalizedAxis
        let end = point(
            x: base.x + axis.x * expected.depth.meters,
            y: base.y + axis.y * expected.depth.meters,
            z: base.z + axis.z * expected.depth.meters
        )
        guard entries.filter({ $0.kind == .body }).count == 1,
              entries.filter({ $0.kind == .face }).count == 6,
              entries.filter({ $0.kind == .edge }).count == 12,
              entries.filter({ $0.kind == .vertex }).count == 8,
              cylinderFaces.count == 4,
              planarFaces.count == 2,
              circularEdges.count == 8,
              seamEdges.count == 4,
              cylinderFaces.allSatisfy({ face in
                  guard let radius = face.surfaceRadius,
                        let observedAxis = face.surfaceAxis,
                        let origin = face.surfaceOrigin else { return false }
                  return tolerance.acceptsLinear(expected: expected.radius.meters, observed: radius)
                      && parallel(observedAxis, axis: axis, tolerance: tolerance)
                      && onAxis(origin, base: base, axis: axis, tolerance: tolerance)
                      && face.edgeCount == 4
              }),
              planarFaces.allSatisfy({ face in
                  guard let normal = face.surfaceNormal,
                        let center = face.center else { return false }
                  return parallel(normal, axis: axis, tolerance: tolerance)
                      && (samePoint(center, base, tolerance: tolerance)
                          || samePoint(center, end, tolerance: tolerance))
              }),
              planarFaces.contains(where: { face in
                  face.center.map { samePoint($0, base, tolerance: tolerance) } == true
              }),
              planarFaces.contains(where: { face in
                  face.center.map { samePoint($0, end, tolerance: tolerance) } == true
              }),
              circularEdges.allSatisfy({ edge in
                  guard let radius = edge.curveRadius,
                        let center = edge.curveCenter,
                        let normal = edge.curveNormal else { return false }
                  return tolerance.acceptsLinear(expected: expected.radius.meters, observed: radius)
                      && parallel(normal, axis: axis, tolerance: tolerance)
                      && (samePoint(center, base, tolerance: tolerance)
                          || samePoint(center, end, tolerance: tolerance))
              }) else {
            throw CADCylinderOracleError.mismatch(
                "The evaluated cylinder contains missing, extra, misplaced, or non-analytic subshapes."
            )
        }

        let vertices = entries.filter({ $0.kind == .vertex }).compactMap(\.start)
        guard vertices.count == 8,
              vertices.allSatisfy({ vertex in
                  let displacement = vector(from: base, to: vertex)
                  let axial = dot(displacement, axis)
                  let radial = subtract(displacement, scaled(axis, by: axial))
                  return (tolerance.acceptsLinear(expected: 0, observed: axial)
                      || tolerance.acceptsLinear(expected: expected.depth.meters, observed: axial))
                      && tolerance.acceptsLinear(
                          expected: expected.radius.meters,
                          observed: length(radial)
                      )
              }) else {
            throw CADCylinderOracleError.mismatch(
                "The evaluated cylinder vertices do not match the directed base, radius, and depth."
            )
        }

        let evaluatedDocument = evaluation.evaluatedDocument
        let bodyIDs = evaluatedDocument.subshapes.entries.compactMap {
            subshapeID, reference -> BodyID? in
            guard subshapeID.featureID == bodyFeatureID,
                  case .body(let bodyID) = reference else { return nil }
            return bodyID
        }
        guard Set(bodyIDs).count == 1, let bodyID = bodyIDs.first else {
            throw CADCylinderOracleError.mismatch(
                "The evaluated primary body reference is missing."
            )
        }
        let volume: Double
        do {
            volume = try evaluatedDocument.brep.volume(
                of: bodyID,
                tolerance: document.modelingSettings.tolerance
            )
        } catch {
            throw CADCylinderOracleError.mismatch(
                "The exact B-rep volume could not be evaluated: \(error)."
            )
        }
        let expectedVolume = Double.pi * expected.radius.meters * expected.radius.meters
            * expected.depth.meters
        guard volume.isFinite,
              volume > 0,
              acceptsVolume(
                  expected: expectedVolume,
                  observed: volume,
                  tolerance: tolerance.modelingTolerance
              ) else {
            throw CADCylinderOracleError.mismatch(
                "The exact B-rep volume does not match the cylinder dimensions."
            )
        }

        return CADCylinderOracleObservation(
            readCount: 2,
            entityCount: source.counts.entityCount,
            featureCount: graph.nodes.count,
            bodyCount: topology.counts.bodyCount,
            faceCount: topology.counts.faceCount,
            edgeCount: topology.counts.edgeCount,
            vertexCount: topology.counts.vertexCount,
            volumeCubicMeters: volume
        )
    }

    private static func point(x: Double, y: Double, z: Double) -> CADPoint3D {
        CADPoint3D(x: x, y: y, z: z, unit: .meter)
    }

    private static func vector(
        from start: CADPoint3D,
        to end: TopologySummaryResult.Entry.Point
    ) -> CADDirection3D {
        CADDirection3D(x: end.x - start.x, y: end.y - start.y, z: end.z - start.z)
    }

    private static func scaled(_ value: CADDirection3D, by scalar: Double) -> CADDirection3D {
        CADDirection3D(x: value.x * scalar, y: value.y * scalar, z: value.z * scalar)
    }

    private static func subtract(
        _ lhs: CADDirection3D,
        _ rhs: CADDirection3D
    ) -> CADDirection3D {
        CADDirection3D(x: lhs.x - rhs.x, y: lhs.y - rhs.y, z: lhs.z - rhs.z)
    }

    private static func dot(_ lhs: CADDirection3D, _ rhs: CADDirection3D) -> Double {
        lhs.x * rhs.x + lhs.y * rhs.y + lhs.z * rhs.z
    }

    private static func length(_ value: CADDirection3D) -> Double {
        hypot(hypot(value.x, value.y), value.z)
    }

    private static func parallel(
        _ observed: TopologySummaryResult.Entry.Point,
        axis: CADDirection3D,
        tolerance: CADBenchmarkTolerancePolicy
    ) -> Bool {
        let observedLength = hypot(hypot(observed.x, observed.y), observed.z)
        guard observedLength.isFinite, observedLength > 0 else { return false }
        let cosine = (observed.x * axis.x + observed.y * axis.y + observed.z * axis.z)
            / observedLength
        return abs(abs(cosine) - 1) <= max(
            tolerance.modelingTolerance.angle,
            tolerance.modelingTolerance.relative * 4
        )
    }

    private static func onAxis(
        _ observed: TopologySummaryResult.Entry.Point,
        base: CADPoint3D,
        axis: CADDirection3D,
        tolerance: CADBenchmarkTolerancePolicy
    ) -> Bool {
        let displacement = CADDirection3D(
            x: observed.x - base.x,
            y: observed.y - base.y,
            z: observed.z - base.z
        )
        let axial = dot(displacement, axis)
        return tolerance.acceptsLinear(
            expected: 0,
            observed: length(subtract(displacement, scaled(axis, by: axial)))
        )
    }

    private static func samePoint(
        _ observed: TopologySummaryResult.Entry.Point,
        _ expected: CADPoint3D,
        tolerance: CADBenchmarkTolerancePolicy
    ) -> Bool {
        tolerance.acceptsLinear(expected: expected.x, observed: observed.x)
            && tolerance.acceptsLinear(expected: expected.y, observed: observed.y)
            && tolerance.acceptsLinear(expected: expected.z, observed: observed.z)
    }

    private static func acceptsArea(
        expected: Double,
        observed: Double,
        radius: Double,
        tolerance: ModelingTolerance
    ) -> Bool {
        guard expected.isFinite, observed.isFinite else { return false }
        let limit = max(
            tolerance.distance * max(radius, tolerance.distance) * 4,
            tolerance.relative * max(expected, observed, tolerance.distance * tolerance.distance)
        )
        return abs(expected - observed) <= limit
    }

    private static func acceptsVolume(
        expected: Double,
        observed: Double,
        tolerance: ModelingTolerance
    ) -> Bool {
        guard expected.isFinite, observed.isFinite else { return false }
        let scale = max(
            abs(expected),
            abs(observed),
            tolerance.distance * tolerance.distance * tolerance.distance
        )
        let limit = max(
            tolerance.distance * tolerance.distance * tolerance.distance * 8,
            tolerance.relative * scale
        )
        return abs(expected - observed) <= limit
    }
}
