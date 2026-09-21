import Foundation
import RupaCore
import RupaKit
import SwiftCAD

enum CADCircleOracleError: Error, Equatable, CustomStringConvertible {
    case mismatch(String)

    var description: String {
        switch self {
        case .mismatch(let reason):
            "Circle oracle mismatch: \(reason)"
        }
    }
}

struct CADCircleOracleObservation: Equatable, Sendable {
    let readCount: Int
    let entityCount: Int
    let featureCount: Int
    let bodyCount: Int
}

/// Exact source observation for an activated analytic-circle case.
enum CADCircleOracle {
    static func evaluate(
        expected: CADCircleChallengeInput,
        challenge: CADChallenge,
        bindings: CADOutputRoleBindings,
        stepResults: [CADCandidateStepResult],
        snapshot: ProjectViewSnapshot
    ) throws -> CADCircleOracleObservation {
        let caseID = challenge.id
        guard CADActivatedCircleCase(rawValue: caseID.rawValue) != nil,
              challenge.category == .circle else {
            throw CADCircleOracleError.mismatch(
                "The oracle received an inactive or non-circle challenge."
            )
        }
        try CADChallengeGeometryValidator.validate(.circle(expected), caseID: caseID)
        let projection: CADCircleChallengeProjection
        do {
            projection = try CADCircleChallengeProjection.decode(challenge)
        } catch {
            throw CADCircleOracleError.mismatch(
                "The candidate-visible circle challenge could not be decoded: \(error)."
            )
        }
        guard projection.orientation == expected.plane,
              projection.center.meters == expected.center.meters,
              projection.radius.meters == expected.radius.meters else {
            throw CADCircleOracleError.mismatch(
                "The candidate-visible challenge and private circle expectation disagree."
            )
        }
        try bindings.validate(for: challenge, availableStepResults: stepResults)
        guard bindings.bindings.count == 1,
              let binding = bindings.bindings.first,
              binding.role == "circle",
              let stepResult = stepResults.first(where: { $0.stepIndex == binding.stepIndex }) else {
            throw CADCircleOracleError.mismatch(
                "The circle role is not bound to one candidate step."
            )
        }
        let featureIDDescription = try binding.selector.resolveFeatureID(
            from: stepResult,
            caseID: caseID,
            role: binding.role
        )
        guard let featureUUID = UUID(uuidString: featureIDDescription) else {
            throw CADCircleOracleError.mismatch("The bound FeatureID is not a tagged UUID.")
        }

        let featureID = FeatureID(featureUUID)
        let document = snapshot.document.document
        let graph = document.cadDocument.designGraph
        let tolerance = try CADBenchmarkTolerancePolicy(
            modelingTolerance: document.modelingSettings.tolerance
        )
        let sourcePlane: SketchPlane
        do {
            sourcePlane = try CADCircleGeometryMapping.sourcePlane(
                orientation: expected.plane,
                targetCenter: expected.center,
                submittedCenter: expected.center,
                modelingTolerance: tolerance.modelingTolerance,
                caseID: caseID
            )
        } catch {
            throw CADCircleOracleError.mismatch(
                "The expected circle plane could not be constructed: \(error)."
            )
        }

        guard graph.order.count == 1,
              graph.nodes.count == 1,
              graph.order.first == featureID,
              let feature = graph.nodes[featureID],
              feature.isSuppressed == false,
              feature.outputs.contains(where: { $0.role == .curve }) else {
            throw CADCircleOracleError.mismatch(
                "The bound feature is not the sole unsuppressed curve source feature."
            )
        }
        guard case .sketch(let sketch) = feature.operation,
              sketch.plane == sourcePlane,
              sketch.entities.count == 1,
              let entity = sketch.entities.values.first,
              case .circle = entity else {
            throw CADCircleOracleError.mismatch(
                "The bound source is not one analytic circle on the expected plane."
            )
        }

        let source: SketchEntitySnapshot
        do {
            source = try SketchEntitySnapshotService().snapshot(
                document: document,
                objectRegistry: snapshot.objectRegistry
            )
        } catch {
            throw CADCircleOracleError.mismatch(
                "The immutable source snapshot could not be read: \(error)."
            )
        }
        guard source.counts.sketchCount == 1,
              source.counts.entityCount == 1,
              source.counts.regionCount == 1,
              source.entries.count == 1,
              source.sketches.count == 1,
              source.regions.count == 1,
              let entry = source.entries.first,
              let sketchEntry = source.sketches.first,
              let region = source.regions.first,
              entry.entityKind == "circle",
              entry.sourceFeatureID == featureIDDescription,
              sketchEntry.sourceFeatureID == featureIDDescription,
              sketchEntry.plane == sourcePlane,
              sketchEntry.entityCount == 1,
              region.sourceFeatureID == featureIDDescription,
              region.plane == sourcePlane,
              region.boundarySegmentCount == 1,
              region.boundaryPointCount == region.boundaryPoints.count,
              region.boundaryPointCount >= 3,
              entry.center != nil,
              entry.radius != nil else {
            throw CADCircleOracleError.mismatch(
                "The immutable source snapshot contains an unexpected circle shape."
            )
        }
        guard let observedCenter = entry.center,
              let observedRadius = entry.radius,
              observedCenter.x.isFinite,
              observedCenter.y.isFinite,
              observedRadius.isFinite else {
            throw CADCircleOracleError.mismatch(
                "The circle source snapshot has no finite center or radius."
            )
        }
        let observedWorldCenter: Point3D
        do {
            observedWorldCenter = try CADCircleGeometryMapping.worldPoint(
                from: observedCenter,
                sourcePlane: sourcePlane,
                modelingTolerance: tolerance.modelingTolerance
            )
        } catch {
            throw CADCircleOracleError.mismatch(
                "The source local center could not be mapped to world space: \(error)."
            )
        }
        let expectedCenter = expected.center.meters
        guard tolerance.acceptsLinear(expected: expectedCenter.x, observed: observedWorldCenter.x),
              tolerance.acceptsLinear(expected: expectedCenter.y, observed: observedWorldCenter.y),
              tolerance.acceptsLinear(expected: expectedCenter.z, observed: observedWorldCenter.z),
              tolerance.isNonDegenerate(expected.radius.meters),
              tolerance.isNonDegenerate(observedRadius),
              tolerance.acceptsLinear(expected: expected.radius.meters, observed: observedRadius),
              tolerance.acceptsLinear(expected: 0.0, observed: region.center.x),
              tolerance.acceptsLinear(expected: 0.0, observed: region.center.y),
              acceptsArea(
                  expected: Double.pi * expected.radius.meters * expected.radius.meters,
                  observed: region.areaSquareMeters,
                  radius: expected.radius.meters,
                  tolerance: tolerance.modelingTolerance
              ),
              snapshot.evaluationSnapshot.bodyCount == 0 else {
            throw CADCircleOracleError.mismatch(
                "The source circle center, radius, plane, or zero-body contract is wrong."
            )
        }

        return CADCircleOracleObservation(
            readCount: 1,
            entityCount: source.counts.entityCount,
            featureCount: graph.nodes.count,
            bodyCount: snapshot.evaluationSnapshot.bodyCount
        )
    }

    private static func acceptsArea(
        expected: Double,
        observed: Double,
        radius: Double,
        tolerance: ModelingTolerance
    ) -> Bool {
        guard expected.isFinite, observed.isFinite else { return false }
        let linearScale = max(radius, tolerance.distance)
        let limit = max(
            tolerance.distance * linearScale * 4.0,
            tolerance.relative * max(expected, observed, tolerance.distance * tolerance.distance)
        )
        return abs(expected - observed) <= limit
    }
}
