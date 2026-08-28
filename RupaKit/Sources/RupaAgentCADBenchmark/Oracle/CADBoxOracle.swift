import Foundation
import RupaCore
import RupaKit
import SwiftCAD

enum CADBoxOracleError: Error, Equatable, CustomStringConvertible {
    case mismatch(String)

    var description: String {
        switch self {
        case .mismatch(let reason):
            "Box oracle mismatch: \(reason)"
        }
    }
}

struct CADBoxOracleObservation: Equatable, Sendable {
    let readCount: Int
    let entityCount: Int
    let featureCount: Int
    let bodyCount: Int
    let faceCount: Int
    let edgeCount: Int
    let vertexCount: Int
    let volumeCubicMeters: Double
}

/// Exact source and B-rep observation for an activated box case.
enum CADBoxOracle {
    private struct LocalPoint: Equatable {
        let x: Double
        let y: Double
    }

    private struct LocalEdge {
        let start: LocalPoint
        let end: LocalPoint
    }

    static func evaluate(
        expected: CADBoxChallengeInput,
        challenge: CADChallenge,
        bindings: CADOutputRoleBindings,
        stepResults: [CADCandidateStepResult],
        snapshot: ProjectViewSnapshot
    ) throws -> CADBoxOracleObservation {
        let caseID = challenge.id
        guard CADActivatedBoxCase(rawValue: caseID.rawValue) != nil,
              challenge.category == .box else {
            throw CADBoxOracleError.mismatch(
                "The oracle received an inactive or non-box challenge."
            )
        }
        try CADChallengeGeometryValidator.validate(.box(expected), caseID: caseID)
        let projection: CADBoxChallengeProjection
        do {
            projection = try CADBoxChallengeProjection.decode(challenge)
        } catch {
            throw CADBoxOracleError.mismatch(
                "The candidate-visible box challenge could not be decoded: \(error)."
            )
        }
        guard projection.origin.meters == expected.origin.meters,
              projection.width.meters == expected.width.meters,
              projection.depth.meters == expected.depth.meters,
              projection.height.meters == expected.height.meters else {
            throw CADBoxOracleError.mismatch(
                "The candidate-visible challenge and private box expectation disagree."
            )
        }

        do {
            try bindings.validate(for: challenge, availableStepResults: stepResults)
        } catch {
            throw CADBoxOracleError.mismatch("The output role bindings are invalid: \(error).")
        }
        guard bindings.bindings.count == 1,
              let binding = bindings.bindings.first,
              binding.role == "solid",
              let stepResult = stepResults.first(where: { $0.stepIndex == binding.stepIndex }) else {
            throw CADBoxOracleError.mismatch(
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
            throw CADBoxOracleError.mismatch("The solid role could not resolve its body feature.")
        }
        guard let featureUUID = UUID(uuidString: featureIDDescription) else {
            throw CADBoxOracleError.mismatch("The bound body FeatureID is not a tagged UUID.")
        }

        let bodyFeatureID = FeatureID(featureUUID)
        let document = snapshot.document.document
        let graph = document.cadDocument.designGraph
        let tolerance = try CADBenchmarkTolerancePolicy(
            modelingTolerance: document.modelingSettings.tolerance
        )
        let sourcePlane: SketchPlane
        do {
            sourcePlane = try CADBoxGeometryMapping.sourcePlane(
                expectedOrigin: expected.origin,
                expectedWidth: expected.width,
                expectedDepth: expected.depth,
                submittedOrigin: expected.origin,
                submittedWidth: expected.width,
                submittedDepth: expected.depth,
                modelingTolerance: tolerance.modelingTolerance,
                caseID: caseID
            )
        } catch {
            throw CADBoxOracleError.mismatch(
                "The expected box source plane could not be constructed: \(error)."
            )
        }

        guard graph.order.count == 2,
              graph.nodes.count == 2,
              graph.nodes.values.filter({ !$0.isSuppressed }).count == 2,
              graph.order.last == bodyFeatureID,
              let sketchFeatureID = graph.order.first,
              let sketchFeature = graph.nodes[sketchFeatureID],
              let bodyFeature = graph.nodes[bodyFeatureID],
              sketchFeature.isSuppressed == false,
              bodyFeature.isSuppressed == false,
              sketchFeature.outputs.contains(where: { $0.role == .profile }),
              bodyFeature.outputs.contains(where: { $0.role == .body }) else {
            throw CADBoxOracleError.mismatch(
                "The box source must contain exactly one unsuppressed sketch and one body."
            )
        }
        guard case .sketch(let sketch) = sketchFeature.operation,
              sketch.plane == sourcePlane,
              sketch.entities.count == 4,
              case .extrude(let extrude) = bodyFeature.operation,
              extrude.profile.featureID == sketchFeatureID,
              extrude.profile.profileIndex == 0,
              extrude.direction == .normal,
              extrude.operation == .newBody else {
            throw CADBoxOracleError.mismatch(
                "The box source is not a normal extrude of a four-line profile."
            )
        }

        guard let bodyNode = document.productMetadata.sceneNodes.values.first(where: {
            $0.reference == .body(bodyFeatureID)
        }),
        let bodyObject = bodyNode.object,
        bodyObject.category == .body,
        bodyObject.geometryRole == .solid,
        bodyObject.typeID == .cube else {
            throw CADBoxOracleError.mismatch(
                "The primary body is not represented as a cube solid."
            )
        }

        let quantity = try document.cadDocument.parameters.resolvedValue(for: extrude.distance)
        guard quantity.kind == .length,
              tolerance.acceptsLinear(expected: expected.height.meters, observed: quantity.value) else {
            throw CADBoxOracleError.mismatch("The extrude depth does not match box height.")
        }

        let source: SketchEntitySnapshot
        do {
            source = try SketchEntitySnapshotService().snapshot(
                document: document,
                objectRegistry: snapshot.objectRegistry
            )
        } catch {
            throw CADBoxOracleError.mismatch(
                "The immutable box source snapshot could not be read: \(error)."
            )
        }
        guard source.counts.sketchCount == 1,
              source.counts.entityCount == 4,
              source.counts.regionCount == 1,
              source.entries.count == 4,
              source.sketches.count == 1,
              source.regions.count == 1,
              let sketchEntry = source.sketches.first,
              let region = source.regions.first,
              sketchEntry.sourceFeatureID == sketchFeatureID.description,
              sketchEntry.plane == sourcePlane,
              sketchEntry.entityCount == 4,
              region.sourceFeatureID == sketchFeatureID.description,
              region.plane == sourcePlane,
              region.boundaryPointCount == 4,
              region.boundarySegmentCount == 4,
              region.boundaryPoints.count == 4,
              source.entries.allSatisfy({
                  $0.sourceFeatureID == sketchFeatureID.description
                      && $0.entityKind == "line"
                      && $0.start != nil
                      && $0.end != nil
              }) else {
            throw CADBoxOracleError.mismatch(
                "The source snapshot is not one closed four-line box profile."
            )
        }

        let halfWidth = expected.width.meters / 2.0
        let halfDepth = expected.depth.meters / 2.0
        var remaining = [
            LocalEdge(
                start: LocalPoint(x: -halfWidth, y: -halfDepth),
                end: LocalPoint(x: halfWidth, y: -halfDepth)
            ),
            LocalEdge(
                start: LocalPoint(x: halfWidth, y: -halfDepth),
                end: LocalPoint(x: halfWidth, y: halfDepth)
            ),
            LocalEdge(
                start: LocalPoint(x: halfWidth, y: halfDepth),
                end: LocalPoint(x: -halfWidth, y: halfDepth)
            ),
            LocalEdge(
                start: LocalPoint(x: -halfWidth, y: halfDepth),
                end: LocalPoint(x: -halfWidth, y: -halfDepth)
            ),
        ]
        for entry in source.entries {
            guard let start = entry.start,
                  let end = entry.end else {
                throw CADBoxOracleError.mismatch("A box profile edge has no endpoints.")
            }
            let observed = LocalEdge(
                start: LocalPoint(x: start.x, y: start.y),
                end: LocalPoint(x: end.x, y: end.y)
            )
            guard let index = remaining.firstIndex(where: {
                edge($0, matches: observed, tolerance: tolerance)
            }) else {
                throw CADBoxOracleError.mismatch(
                    "A box profile edge does not match the expected width, depth, or closure."
                )
            }
            remaining.remove(at: index)
        }
        guard remaining.isEmpty,
              tolerance.acceptsLinear(expected: 0.0, observed: region.center.x),
              tolerance.acceptsLinear(expected: 0.0, observed: region.center.y),
              acceptsArea(
                  expected: expected.width.meters * expected.depth.meters,
                  observed: region.areaSquareMeters,
                  width: expected.width.meters,
                  height: expected.depth.meters,
                  tolerance: tolerance.modelingTolerance
              ) else {
            throw CADBoxOracleError.mismatch(
                "The box profile center, area, boundary, or dimensions are wrong."
            )
        }

        for entry in source.entries {
            guard let localStart = entry.start,
                  let localEnd = entry.end else {
                throw CADBoxOracleError.mismatch("A box profile edge has no world endpoints.")
            }
            let start = try CADRectangleGeometryMapping.worldPoint(
                from: localStart,
                sourcePlane: sourcePlane,
                modelingTolerance: tolerance.modelingTolerance
            )
            let end = try CADRectangleGeometryMapping.worldPoint(
                from: localEnd,
                sourcePlane: sourcePlane,
                modelingTolerance: tolerance.modelingTolerance
            )
            let origin = expected.origin.meters
            let maxX = origin.x + expected.width.meters
            let maxY = origin.y + expected.depth.meters
            guard [start, end].allSatisfy({ point in
                (tolerance.acceptsLinear(expected: origin.x, observed: point.x)
                    || tolerance.acceptsLinear(expected: maxX, observed: point.x))
                    && (tolerance.acceptsLinear(expected: origin.y, observed: point.y)
                        || tolerance.acceptsLinear(expected: maxY, observed: point.y))
                    && tolerance.acceptsLinear(expected: origin.z, observed: point.z)
            }) else {
                throw CADBoxOracleError.mismatch(
                    "The profile world bounds do not match the lower-corner box origin."
                )
            }
        }

        guard let evaluation = snapshot.cadInteraction else {
            throw CADBoxOracleError.mismatch("The final view has no immutable CAD evaluation.")
        }
        let evaluatedDocument = evaluation.evaluatedDocument
        let topology: TopologySnapshot
        do {
            topology = try TopologySnapshotService().snapshot(
                document: document,
                objectRegistry: snapshot.objectRegistry,
                currentEvaluation: evaluation,
                currentGeneration: snapshot.documentGeneration
            )
        } catch {
            throw CADBoxOracleError.mismatch(
                "The immutable evaluated B-rep could not be read: \(error)."
            )
        }
        guard topology.counts.bodyCount == 1,
              topology.counts.faceCount == 6,
              topology.counts.edgeCount == 12,
              topology.counts.vertexCount == 8 else {
            throw CADBoxOracleError.mismatch(
                "The evaluated box topology must contain 1 body, 6 faces, 12 edges, and 8 vertices."
            )
        }
        let bodyEntries = topology.entries.filter {
            $0.sourceFeatureID == bodyFeatureID.description
        }
        guard bodyEntries.count == 27,
              bodyEntries.filter({ $0.kind == .body }).count == 1,
              bodyEntries.filter({ $0.kind == .face }).count == 6,
              bodyEntries.filter({ $0.kind == .edge }).count == 12,
              bodyEntries.filter({ $0.kind == .vertex }).count == 8,
              bodyEntries.filter({ $0.kind == .face }).allSatisfy({
                  $0.surfaceKind == "plane"
                      && $0.surfaceNormal != nil
                      && $0.surfaceOrigin != nil
                      && $0.edgeCount == 4
              }),
              bodyEntries.filter({ $0.kind == .edge }).allSatisfy({
                  $0.curveKind == "line"
                      && $0.curveOrigin != nil
                      && $0.curveDirection != nil
                      && $0.start != nil
                      && $0.end != nil
              }) else {
            throw CADBoxOracleError.mismatch(
                "The evaluated box topology contains missing, extra, or non-analytic subshapes."
            )
        }

        let origin = expected.origin.meters
        let maxX = origin.x + expected.width.meters
        let maxY = origin.y + expected.depth.meters
        let maxZ = origin.z + expected.height.meters
        let vertices = bodyEntries.filter({ $0.kind == .vertex }).compactMap(\.start)
        guard vertices.count == 8,
              vertices.allSatisfy({ point in
                  (tolerance.acceptsLinear(expected: origin.x, observed: point.x)
                      || tolerance.acceptsLinear(expected: maxX, observed: point.x))
                      && (tolerance.acceptsLinear(expected: origin.y, observed: point.y)
                          || tolerance.acceptsLinear(expected: maxY, observed: point.y))
                      && (tolerance.acceptsLinear(expected: origin.z, observed: point.z)
                          || tolerance.acceptsLinear(expected: maxZ, observed: point.z))
              }) else {
            throw CADBoxOracleError.mismatch("The evaluated box vertices do not match world bounds.")
        }

        let bodyIDs = evaluatedDocument.subshapes.entries.compactMap {
            subshapeID, reference -> BodyID? in
            guard subshapeID.featureID == bodyFeatureID,
                  case .body(let bodyID) = reference else {
                return nil
            }
            return bodyID
        }
        guard Set(bodyIDs).count == 1,
              let bodyID = bodyIDs.first else {
            throw CADBoxOracleError.mismatch("The evaluated primary body reference is missing.")
        }
        let volume: Double
        do {
            volume = try evaluatedDocument.brep.volume(
                of: bodyID,
                tolerance: document.modelingSettings.tolerance
            )
        } catch {
            throw CADBoxOracleError.mismatch("The exact B-rep volume could not be evaluated: \(error).")
        }
        let expectedVolume = expected.width.meters * expected.depth.meters * expected.height.meters
        guard volume.isFinite,
              volume > 0.0,
              acceptsVolume(
                  expected: expectedVolume,
                  observed: volume,
                  tolerance: tolerance.modelingTolerance
              ) else {
            throw CADBoxOracleError.mismatch("The exact B-rep volume does not match the box dimensions.")
        }

        return CADBoxOracleObservation(
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

    private static func edge(
        _ expected: LocalEdge,
        matches observed: LocalEdge,
        tolerance: CADBenchmarkTolerancePolicy
    ) -> Bool {
        (point(expected.start, matches: observed.start, tolerance: tolerance)
            && point(expected.end, matches: observed.end, tolerance: tolerance))
            || (point(expected.start, matches: observed.end, tolerance: tolerance)
                && point(expected.end, matches: observed.start, tolerance: tolerance))
    }

    private static func point(
        _ expected: LocalPoint,
        matches observed: LocalPoint,
        tolerance: CADBenchmarkTolerancePolicy
    ) -> Bool {
        tolerance.acceptsLinear(expected: expected.x, observed: observed.x)
            && tolerance.acceptsLinear(expected: expected.y, observed: observed.y)
    }

    private static func acceptsArea(
        expected: Double,
        observed: Double,
        width: Double,
        height: Double,
        tolerance: ModelingTolerance
    ) -> Bool {
        guard expected.isFinite, observed.isFinite else { return false }
        let linearScale = max(width, height, tolerance.distance)
        let limit = max(
            tolerance.distance * linearScale * 4.0,
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
        let scale = max(abs(expected), abs(observed), tolerance.distance * tolerance.distance * tolerance.distance)
        let limit = max(
            tolerance.distance * tolerance.distance * tolerance.distance * 8.0,
            tolerance.relative * scale
        )
        return abs(expected - observed) <= limit
    }
}
