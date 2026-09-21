import Foundation
import RupaCore
import RupaKit
import SwiftCAD

enum CADCompoundOracleError: Error, Equatable, CustomStringConvertible {
    case mismatch(String)

    var description: String {
        switch self {
        case .mismatch(let reason):
            "Compound oracle mismatch: \(reason)"
        }
    }
}

struct CADCompoundOracleObservation: Equatable, Sendable {
    let memberCount: Int
    let readCount: Int
    let entityCount: Int
    let featureCount: Int
    let bodyCount: Int
    let faceCount: Int
    let edgeCount: Int
    let vertexCount: Int
    let volumeCubicMeters: Double
}

/// Exact source and B-rep observation for one compound preparation case.
///
/// The oracle receives the private member values only after the production
/// batch has returned an immutable final view. It compares those values with
/// the candidate-visible projection, then checks every ordered member's source
/// feature and independent evaluated body.
enum CADCompoundOracle {
    static func evaluate(
        expected: CADCompoundChallengeInput,
        challenge: CADChallenge,
        bindings: CADOutputRoleBindings,
        stepResults: [CADCandidateStepResult],
        snapshot: ProjectViewSnapshot
    ) throws -> CADCompoundOracleObservation {
        let caseID = challenge.id
        guard CADActivatedCompoundCase(rawValue: caseID.rawValue) != nil,
              challenge.category == .compound else {
            throw CADCompoundOracleError.mismatch(
                "The oracle received an inactive or non-compound challenge."
            )
        }
        try expected.validate(caseID: caseID)
        let projection: CADCompoundChallengeProjection
        do {
            projection = try CADCompoundChallengeProjection.decode(challenge)
        } catch {
            throw CADCompoundOracleError.mismatch(
                "The candidate-visible compound challenge could not be decoded: \(error)."
            )
        }
        guard projection.members.count == expected.members.count else {
            throw CADCompoundOracleError.mismatch(
                "The candidate-visible member count disagrees with the private expectation."
            )
        }
        for (publicMember, expectedMember) in zip(projection.members, expected.members) {
            guard publicMember.role == expectedMember.role,
                  publicMember.primitive == expectedMember.primitive else {
                throw CADCompoundOracleError.mismatch(
                    "The candidate-visible compound member roles or primitive types disagree with the private expectation."
                )
            }
            switch expectedMember.primitive {
            case .box:
                guard publicMember.box == expectedMember.box,
                      publicMember.cylinder == nil else {
                    throw CADCompoundOracleError.mismatch(
                        "The submitted box member values disagree with the private expectation."
                    )
                }
            case .cylinder:
                guard publicMember.cylinder == expectedMember.cylinder,
                      publicMember.box == nil else {
                    throw CADCompoundOracleError.mismatch(
                        "The submitted cylinder member values or axis disagree with the private expectation."
                    )
                }
            }
        }

        do {
            try bindings.validate(for: challenge, availableStepResults: stepResults)
        } catch {
            throw CADCompoundOracleError.mismatch(
                "The compound output role bindings are invalid: \(error)."
            )
        }
        guard bindings.bindings.count == expected.members.count,
              stepResults.count == expected.members.count,
              bindings.bindings.map(\.role) == expected.members.map(\.role),
              bindings.bindings.enumerated().allSatisfy({ index, binding in
                  binding.stepIndex == index && binding.selector == .primary
              }),
              stepResults.enumerated().allSatisfy({ index, step in
                  step.stepIndex == index && step.status == .published
              }) else {
            throw CADCompoundOracleError.mismatch(
                "Compound member output roles must preserve the declared order."
            )
        }

        let document = snapshot.document.document
        let graph = document.cadDocument.designGraph
        guard graph.order.count == expected.members.count * 2,
              graph.nodes.count == expected.members.count * 2,
              graph.nodes.values.allSatisfy({ !$0.isSuppressed }) else {
            throw CADCompoundOracleError.mismatch(
                "The compound source must contain exactly two active features per member."
            )
        }
        let tolerance: CADBenchmarkTolerancePolicy
        do {
            tolerance = try CADBenchmarkTolerancePolicy(
                modelingTolerance: document.modelingSettings.tolerance
            )
        } catch {
            throw CADCompoundOracleError.mismatch(
                "The compound document tolerance is invalid: \(error)."
            )
        }

        let source: SketchEntitySnapshot
        do {
            source = try SketchEntitySnapshotService().snapshot(
                document: document,
                objectRegistry: snapshot.objectRegistry
            )
        } catch {
            throw CADCompoundOracleError.mismatch(
                "The immutable compound source snapshot could not be read: \(error)."
            )
        }
        let expectedEntityCount = expected.members.reduce(into: 0) { count, member in
            count += member.primitive == .box ? 4 : 1
        }
        guard source.counts.sketchCount == expected.members.count,
              source.counts.entityCount == expectedEntityCount,
              source.counts.regionCount == expected.members.count else {
            throw CADCompoundOracleError.mismatch(
                "The compound source contains missing or extra sketch entities or profile regions."
            )
        }

        var bodyFeatureIDs: [FeatureID] = []
        bodyFeatureIDs.reserveCapacity(expected.members.count)
        for index in expected.members.indices {
            let member = expected.members[index]
            let publicMember = projection.members[index]
            let step = stepResults[index]
            let binding = bindings.bindings[index]
            guard step.createdFeatureIDs.count == 2,
                  step.primaryFeatureID == step.createdFeatureIDs.last,
                  let sketchUUID = UUID(uuidString: step.createdFeatureIDs[0]),
                  let bodyUUID = UUID(uuidString: step.createdFeatureIDs[1]) else {
                throw CADCompoundOracleError.mismatch(
                    "Compound member \(member.role) does not retain two tagged source features."
                )
            }
            let sketchFeatureID = FeatureID(sketchUUID)
            let bodyFeatureID = FeatureID(bodyUUID)
            let selectedFeatureID: String
            do {
                selectedFeatureID = try binding.selector.resolveFeatureID(
                    from: step,
                    caseID: caseID,
                    role: binding.role
                )
            } catch {
                throw CADCompoundOracleError.mismatch(
                    "Compound member \(member.role) has an unresolved output binding."
                )
            }
            guard binding.role == member.role,
                  selectedFeatureID == bodyFeatureID.description,
                  graph.order[index * 2] == sketchFeatureID,
                  graph.order[index * 2 + 1] == bodyFeatureID,
                  let sketchFeature = graph.nodes[sketchFeatureID],
                  let bodyFeature = graph.nodes[bodyFeatureID],
                  sketchFeature.isSuppressed == false,
                  bodyFeature.isSuppressed == false,
                  sketchFeature.outputs.contains(where: { $0.role == .profile }),
                  bodyFeature.outputs.contains(where: { $0.role == .body }),
                  case .sketch(let sketch) = sketchFeature.operation,
                  case .extrude(let extrude) = bodyFeature.operation else {
                throw CADCompoundOracleError.mismatch(
                    "Compound member \(member.role) does not retain its ordered sketch/body source pair."
                )
            }

            let sourcePlane: SketchPlane
            do {
                sourcePlane = try expectedSourcePlane(
                    member: member,
                    caseID: caseID
                )
            } catch {
                throw CADCompoundOracleError.mismatch(
                    "The expected source plane for member \(member.role) could not be constructed: \(error)."
                )
            }
            guard sketch.plane == sourcePlane,
                  extrude.profile.featureID == sketchFeatureID,
                  extrude.profile.profileIndex == 0,
                  extrude.direction == .normal,
                  extrude.operation == .newBody else {
                throw CADCompoundOracleError.mismatch(
                    "Compound member \(member.role) has the wrong plane, profile, or extrusion direction."
                )
            }

            guard let bodyNode = document.productMetadata.sceneNodes.values.first(where: {
                $0.reference == .body(bodyFeatureID)
            }),
            let bodyObject = bodyNode.object,
            bodyObject.category == .body,
            bodyObject.geometryRole == .solid,
            bodyObject.typeID == (member.primitive == .box ? .cube : .cylinder) else {
                throw CADCompoundOracleError.mismatch(
                    "Compound member \(member.role) is not represented by its declared independent solid type."
                )
            }
            let depthExpression = try document.cadDocument.parameters.resolvedValue(
                for: extrude.distance
            )
            let expectedDepth: Double
            switch member.primitive {
            case .box:
                guard let box = member.box else {
                    throw CADCompoundOracleError.mismatch(
                        "Box member \(member.role) has no private box payload."
                    )
                }
                expectedDepth = box.height.meters
            case .cylinder:
                guard let cylinder = member.cylinder else {
                    throw CADCompoundOracleError.mismatch(
                        "Cylinder member \(member.role) has no private cylinder payload."
                    )
                }
                expectedDepth = cylinder.depth.meters
            }
            guard depthExpression.kind == .length,
                  tolerance.acceptsLinear(
                      expected: expectedDepth,
                      observed: depthExpression.value
                  ) else {
                throw CADCompoundOracleError.mismatch(
                    "Compound member \(member.role) has the wrong extrusion depth."
                )
            }

            try verifySourceSketch(
                member: member,
                publicMember: publicMember,
                sketchFeatureID: sketchFeatureID,
                source: source,
                sourcePlane: sourcePlane,
                tolerance: tolerance,
                caseID: caseID
            )
            bodyFeatureIDs.append(bodyFeatureID)
        }

        guard let evaluation = snapshot.cadInteraction else {
            throw CADCompoundOracleError.mismatch(
                "The final view has no immutable compound evaluation."
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
            throw CADCompoundOracleError.mismatch(
                "The immutable evaluated compound B-rep could not be read: \(error)."
            )
        }
        let memberCount = expected.members.count
        guard topology.counts.bodyCount == memberCount,
              topology.counts.faceCount == memberCount * 6,
              topology.counts.edgeCount == memberCount * 12,
              topology.counts.vertexCount == memberCount * 8 else {
            throw CADCompoundOracleError.mismatch(
                "The evaluated compound topology has missing or extra independent bodies."
            )
        }

        var totalVolume = 0.0
        let evaluatedDocument = evaluation.evaluatedDocument
        for (index, member) in expected.members.enumerated() {
            let bodyFeatureID = bodyFeatureIDs[index]
            let entries = topology.entries.filter {
                $0.sourceFeatureID == bodyFeatureID.description
            }
            let bodies = entries.filter { $0.kind == .body }
            let faces = entries.filter { $0.kind == .face }
            let edges = entries.filter { $0.kind == .edge }
            let vertices = entries.filter { $0.kind == .vertex }
            guard bodies.count == 1,
                  faces.count == 6,
                  edges.count == 12,
                  vertices.count == 8 else {
                throw CADCompoundOracleError.mismatch(
                    "Compound member \(member.role) does not have one complete independent B-rep body."
                )
            }
            switch member.primitive {
            case .box:
                try verifyBoxTopology(
                    member: member,
                    faces: faces,
                    vertices: vertices,
                    tolerance: tolerance,
                    caseID: caseID
                )
            case .cylinder:
                try verifyCylinderTopology(
                    member: member,
                    faces: faces,
                    edges: edges,
                    vertices: vertices,
                    tolerance: tolerance,
                    caseID: caseID
                )
            }
            guard let bodyID = evaluatedDocument.subshapes.entries.compactMap({
                subshapeID, reference -> BodyID? in
                guard subshapeID.featureID == bodyFeatureID,
                      case .body(let bodyID) = reference else { return nil }
                return bodyID
            }).first else {
                throw CADCompoundOracleError.mismatch(
                    "Compound member \(member.role) has no evaluated body reference."
                )
            }
            let volume: Double
            do {
                volume = try evaluatedDocument.brep.volume(
                    of: bodyID,
                    tolerance: document.modelingSettings.tolerance
                )
            } catch {
                throw CADCompoundOracleError.mismatch(
                    "The exact B-rep volume for member \(member.role) could not be evaluated: \(error)."
                )
            }
            let expectedVolume: Double
            switch member.primitive {
            case .box:
                guard let input = member.box else {
                    throw CADCompoundOracleError.mismatch(
                        "Box member \(member.role) has no private box payload."
                    )
                }
                expectedVolume = input.width.meters * input.depth.meters * input.height.meters
            case .cylinder:
                guard let input = member.cylinder else {
                    throw CADCompoundOracleError.mismatch(
                        "Cylinder member \(member.role) has no private cylinder payload."
                    )
                }
                expectedVolume = .pi * input.radius.meters * input.radius.meters * input.depth.meters
            }
            guard volume.isFinite,
                  volume > 0,
                  acceptsVolume(
                      expected: expectedVolume,
                      observed: volume,
                      tolerance: tolerance.modelingTolerance
                  ) else {
                throw CADCompoundOracleError.mismatch(
                    "The exact B-rep volume for member \(member.role) is incorrect."
                )
            }
            totalVolume += volume
        }

        return CADCompoundOracleObservation(
            memberCount: memberCount,
            readCount: 2,
            entityCount: source.counts.entityCount,
            featureCount: graph.nodes.count,
            bodyCount: topology.counts.bodyCount,
            faceCount: topology.counts.faceCount,
            edgeCount: topology.counts.edgeCount,
            vertexCount: topology.counts.vertexCount,
            volumeCubicMeters: totalVolume
        )
    }

    private static func expectedSourcePlane(
        member: CADCompoundMemberInput,
        caseID: CADBenchmarkCaseID
    ) throws -> SketchPlane {
        switch member.primitive {
        case .box:
            guard let box = member.box else {
                throw CADCompoundOracleError.mismatch("Box member has no box payload.")
            }
            return try CADBoxGeometryMapping.sourcePlane(
                submittedOrigin: box.origin,
                submittedWidth: box.width,
                submittedDepth: box.depth,
                caseID: caseID
            )
        case .cylinder:
            guard let cylinder = member.cylinder else {
                throw CADCompoundOracleError.mismatch("Cylinder member has no cylinder payload.")
            }
            return try CADCylinderGeometryMapping.commandGeometry(
                baseCenter: cylinder.baseCenter,
                axis: cylinder.axis,
                caseID: caseID
            ).plane
        }
    }

    private static func verifySourceSketch(
        member: CADCompoundMemberInput,
        publicMember: CADCompoundChallengeProjection.Member,
        sketchFeatureID: FeatureID,
        source: SketchEntitySnapshot,
        sourcePlane: SketchPlane,
        tolerance: CADBenchmarkTolerancePolicy,
        caseID: CADBenchmarkCaseID
    ) throws {
        let featureDescription = sketchFeatureID.description
        guard let sketchEntry = source.sketches.first(where: {
            $0.sourceFeatureID == featureDescription
        }),
        sketchEntry.plane == sourcePlane else {
            throw CADCompoundOracleError.mismatch(
                "The source sketch for member \(member.role) has the wrong plane."
            )
        }
        let entries = source.entries.filter { $0.sourceFeatureID == featureDescription }
        guard let region = source.regions.first(where: {
            $0.sourceFeatureID == featureDescription
        }) else {
            throw CADCompoundOracleError.mismatch(
                "The source profile region for member \(member.role) is missing."
            )
        }
        switch member.primitive {
        case .box:
            guard let input = member.box,
                  publicMember.box == input,
                  sketchEntry.entityCount == 4,
                  entries.count == 4,
                  entries.allSatisfy({
                      $0.entityKind == "line" && $0.start != nil && $0.end != nil
                  }),
                  region.plane == sourcePlane,
                  region.boundaryPointCount == 4,
                  region.boundarySegmentCount == 4,
                  region.boundaryPoints.count == 4,
                  tolerance.acceptsLinear(expected: 0, observed: region.center.x),
                  tolerance.acceptsLinear(expected: 0, observed: region.center.y),
                  acceptsArea(
                      expected: input.width.meters * input.depth.meters,
                      observed: region.areaSquareMeters,
                      tolerance: tolerance.modelingTolerance
                  ) else {
                throw CADCompoundOracleError.mismatch(
                    "The source box profile for member \(member.role) is not exact."
                )
            }
            let origin = input.origin.meters
            let maximum = CADPoint3D(
                x: origin.x + input.width.meters,
                y: origin.y + input.depth.meters,
                z: origin.z,
                unit: .meter
            )
            for entry in entries {
                guard let start = entry.start,
                      let end = entry.end else {
                    throw CADCompoundOracleError.mismatch(
                        "The source box profile for member \(member.role) has an incomplete edge."
                    )
                }
                let startWorld = try CADRectangleGeometryMapping.worldPoint(
                    from: start,
                    sourcePlane: sourcePlane,
                    modelingTolerance: tolerance.modelingTolerance
                )
                let endWorld = try CADRectangleGeometryMapping.worldPoint(
                    from: end,
                    sourcePlane: sourcePlane,
                    modelingTolerance: tolerance.modelingTolerance
                )
                guard [startWorld, endWorld].allSatisfy({ point in
                    let xMatches = tolerance.acceptsLinear(expected: origin.x, observed: point.x)
                        || tolerance.acceptsLinear(expected: maximum.x, observed: point.x)
                    let yMatches = tolerance.acceptsLinear(expected: origin.y, observed: point.y)
                        || tolerance.acceptsLinear(expected: maximum.y, observed: point.y)
                    return xMatches && yMatches
                        && tolerance.acceptsLinear(expected: origin.z, observed: point.z)
                }) else {
                    throw CADCompoundOracleError.mismatch(
                        "The source box placement for member \(member.role) is incorrect."
                    )
                }
            }
        case .cylinder:
            guard let input = member.cylinder,
                  publicMember.cylinder == input,
                  sketchEntry.entityCount == 1,
                  entries.count == 1,
                  let entry = entries.first,
                  entry.entityKind == "circle",
                  let center = entry.center,
                  let radius = entry.radius,
                  region.plane == sourcePlane,
                  region.boundarySegmentCount == 1,
                  tolerance.acceptsLinear(expected: 0, observed: center.x),
                  tolerance.acceptsLinear(expected: 0, observed: center.y),
                  tolerance.acceptsLinear(expected: input.radius.meters, observed: radius),
                  tolerance.acceptsLinear(expected: 0, observed: region.center.x),
                  tolerance.acceptsLinear(expected: 0, observed: region.center.y),
                  acceptsArea(
                      expected: .pi * input.radius.meters * input.radius.meters,
                      observed: region.areaSquareMeters,
                      tolerance: tolerance.modelingTolerance
                  ) else {
                throw CADCompoundOracleError.mismatch(
                    "The source cylinder profile for member \(member.role) is not exact."
                )
            }
        }
    }

    private static func verifyBoxTopology(
        member: CADCompoundMemberInput,
        faces: [TopologySummaryResult.Entry],
        vertices: [TopologySummaryResult.Entry],
        tolerance: CADBenchmarkTolerancePolicy,
        caseID _: CADBenchmarkCaseID
    ) throws {
        guard let input = member.box,
              faces.allSatisfy({ $0.surfaceKind == "plane" }),
              vertices.count == 8 else {
            throw CADCompoundOracleError.mismatch(
                "The evaluated box member \(member.role) is not a six-face closed solid."
            )
        }
        let origin = input.origin.meters
        let limits = [
            (origin.x, origin.x + input.width.meters),
            (origin.y, origin.y + input.depth.meters),
            (origin.z, origin.z + input.height.meters),
        ]
        guard vertices.allSatisfy({ vertex in
            guard let point = vertex.start else { return false }
            return [point.x, point.y, point.z].enumerated().allSatisfy { index, value in
                tolerance.acceptsLinear(expected: limits[index].0, observed: value)
                    || tolerance.acceptsLinear(expected: limits[index].1, observed: value)
            }
        }) else {
            throw CADCompoundOracleError.mismatch(
                "The evaluated box member \(member.role) has incorrect placement or dimensions."
            )
        }
    }

    private static func verifyCylinderTopology(
        member: CADCompoundMemberInput,
        faces: [TopologySummaryResult.Entry],
        edges: [TopologySummaryResult.Entry],
        vertices: [TopologySummaryResult.Entry],
        tolerance: CADBenchmarkTolerancePolicy,
        caseID _: CADBenchmarkCaseID
    ) throws {
        guard let input = member.cylinder else {
            throw CADCompoundOracleError.mismatch("Cylinder member has no cylinder payload.")
        }
        let geometry: CADCylinderGeometryMapping.CommandGeometry
        do {
            geometry = try CADCylinderGeometryMapping.commandGeometry(
                baseCenter: input.baseCenter,
                axis: input.axis,
                caseID: "CMP-ORACLE"
            )
        } catch {
            throw CADCompoundOracleError.mismatch(
                "The evaluated cylinder member \(member.role) has an invalid expected axis: \(error)."
            )
        }
        let axis = geometry.normalizedAxis
        let base = input.baseCenter.meters
        let end = CADPoint3D(
            x: base.x + axis.x * input.depth.meters,
            y: base.y + axis.y * input.depth.meters,
            z: base.z + axis.z * input.depth.meters,
            unit: .meter
        )
        let cylinderFaces = faces.filter { $0.surfaceKind == "cylinder" }
        let planarFaces = faces.filter { $0.surfaceKind == "plane" }
        let circularEdges = edges.filter { $0.curveKind == "circle" }
        guard cylinderFaces.count == 4,
              planarFaces.count == 2,
              circularEdges.count == 8,
              cylinderFaces.allSatisfy({ face in
                  guard let radius = face.surfaceRadius,
                        let observedAxis = face.surfaceAxis,
                        let origin = face.surfaceOrigin else { return false }
                  return tolerance.acceptsLinear(expected: input.radius.meters, observed: radius)
                      && parallel(observedAxis, axis: axis, tolerance: tolerance)
                      && onAxis(origin, base: base, axis: axis, tolerance: tolerance)
              }),
              planarFaces.allSatisfy({ face in
                  guard let normal = face.surfaceNormal,
                        let center = face.center else { return false }
                  return parallel(normal, axis: axis, tolerance: tolerance)
                      && (samePoint(center, base, tolerance: tolerance)
                          || samePoint(center, end, tolerance: tolerance))
              }),
              circularEdges.allSatisfy({ edge in
                  guard let radius = edge.curveRadius,
                        let center = edge.curveCenter,
                        let normal = edge.curveNormal else { return false }
                  return tolerance.acceptsLinear(expected: input.radius.meters, observed: radius)
                      && parallel(normal, axis: axis, tolerance: tolerance)
                      && (samePoint(center, base, tolerance: tolerance)
                          || samePoint(center, end, tolerance: tolerance))
              }) else {
            throw CADCompoundOracleError.mismatch(
                "The evaluated cylinder member \(member.role) has missing, extra, or misplaced analytic subshapes."
            )
        }
        guard vertices.allSatisfy({ vertex in
            guard let point = vertex.start else { return false }
            let displacement = CADDirection3D(
                x: point.x - base.x,
                y: point.y - base.y,
                z: point.z - base.z
            )
            let axial = dot(displacement, axis)
            let radial = subtract(displacement, scaled(axis, by: axial))
            return (tolerance.acceptsLinear(expected: 0, observed: axial)
                || tolerance.acceptsLinear(expected: input.depth.meters, observed: axial))
                && tolerance.acceptsLinear(
                    expected: input.radius.meters,
                    observed: length(radial)
                )
        }) else {
            throw CADCompoundOracleError.mismatch(
                "The evaluated cylinder member \(member.role) has incorrect axis, placement, or radius."
            )
        }
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

    private static func acceptsArea(
        expected: Double,
        observed: Double,
        tolerance: ModelingTolerance
    ) -> Bool {
        guard expected.isFinite, observed.isFinite else { return false }
        let limit = max(
            tolerance.distance * max(sqrt(max(expected, 0)), tolerance.distance) * 4,
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
