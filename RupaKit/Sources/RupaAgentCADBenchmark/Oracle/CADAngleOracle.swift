import Foundation
import RupaCore
import RupaKit
import SwiftCAD

enum CADAngleOracleError: Error, Equatable, CustomStringConvertible {
    case mismatch(String)

    var description: String {
        switch self {
        case .mismatch(let reason):
            "Angle oracle mismatch: \(reason)"
        }
    }
}

struct CADAngleOracleObservation: Equatable, Sendable {
    let readCount: Int
    let entityCount: Int
    let featureCount: Int
    let bodyCount: Int
}

/// Exact immutable source observation for an activated two-segment angle case.
enum CADAngleOracle {
    static func evaluate(
        expected: CADAngleChallengeInput,
        challenge: CADChallenge,
        bindings: CADOutputRoleBindings,
        stepResults: [CADCandidateStepResult],
        snapshot: ProjectViewSnapshot
    ) throws -> CADAngleOracleObservation {
        let caseID = challenge.id
        guard CADActivatedAngleCase(rawValue: caseID.rawValue) != nil,
              challenge.category == .angle else {
            throw CADAngleOracleError.mismatch(
                "The oracle received an inactive or non-angle challenge."
            )
        }
        try CADChallengeGeometryValidator.validate(.angle(expected), caseID: caseID)
        let projection: CADAngleChallengeProjection
        do {
            projection = try CADAngleChallengeProjection.decode(challenge)
        } catch {
            throw CADAngleOracleError.mismatch(
                "The candidate-visible angle challenge could not be decoded: \(error)."
            )
        }
        guard projection.orientation == expected.plane,
              projection.intersection.meters == expected.intersection.meters,
              projection.firstDirection == expected.firstDirection,
              projection.secondDirection == expected.secondDirection,
              projection.firstLength.meters == expected.firstLength.meters,
              projection.secondLength.meters == expected.secondLength.meters,
              projection.includedAngle.radians == expected.includedAngle.radians else {
            throw CADAngleOracleError.mismatch(
                "The candidate-visible challenge and private angle expectation disagree."
            )
        }

        do {
            try bindings.validate(for: challenge, availableStepResults: stepResults)
        } catch {
            throw CADAngleOracleError.mismatch("The output role bindings are invalid: \(error).")
        }
        guard bindings.bindings.count == 2,
              stepResults.count == 2,
              let firstBinding = bindings.bindings.first(where: { $0.role == "first-line" }),
              let secondBinding = bindings.bindings.first(where: { $0.role == "second-line" }),
              firstBinding.stepIndex == 0,
              secondBinding.stepIndex == 1,
              firstBinding.selector == .primary,
              secondBinding.selector == .primary,
              let firstStep = stepResults.first(where: { $0.stepIndex == 0 }),
              let secondStep = stepResults.first(where: { $0.stepIndex == 1 }) else {
            throw CADAngleOracleError.mismatch(
                "The two angle roles are not bound to their ordered production steps."
            )
        }
        let firstDescription: String
        let secondDescription: String
        do {
            firstDescription = try firstBinding.selector.resolveFeatureID(
                from: firstStep,
                caseID: caseID,
                role: firstBinding.role
            )
            secondDescription = try secondBinding.selector.resolveFeatureID(
                from: secondStep,
                caseID: caseID,
                role: secondBinding.role
            )
        } catch {
            throw CADAngleOracleError.mismatch("An angle role could not resolve its source feature.")
        }
        guard firstDescription != secondDescription,
              let firstUUID = UUID(uuidString: firstDescription),
              let secondUUID = UUID(uuidString: secondDescription) else {
            throw CADAngleOracleError.mismatch(
                "The angle roles must resolve two distinct tagged FeatureIDs."
            )
        }

        let firstFeatureID = FeatureID(firstUUID)
        let secondFeatureID = FeatureID(secondUUID)
        let document = snapshot.document.document
        let graph = document.cadDocument.designGraph
        let tolerance = try CADBenchmarkTolerancePolicy(
            modelingTolerance: document.modelingSettings.tolerance
        )
        let sourcePlane: SketchPlane
        do {
            sourcePlane = try CADAngleGeometryMapping.sourcePlane(
                orientation: expected.plane,
                intersection: expected.intersection,
                modelingTolerance: tolerance.modelingTolerance,
                caseID: caseID
            )
        } catch {
            throw CADAngleOracleError.mismatch(
                "The expected angle source plane could not be constructed: \(error)."
            )
        }

        guard graph.order == [firstFeatureID, secondFeatureID],
              graph.nodes.count == 2,
              let firstFeature = graph.nodes[firstFeatureID],
              let secondFeature = graph.nodes[secondFeatureID],
              isOneLine(firstFeature, on: sourcePlane),
              isOneLine(secondFeature, on: sourcePlane) else {
            throw CADAngleOracleError.mismatch(
                "The bound features are not the only two ordered unsuppressed line sources."
            )
        }

        let source: SketchEntitySnapshot
        do {
            source = try SketchEntitySnapshotService().snapshot(
                document: document,
                objectRegistry: snapshot.objectRegistry
            )
        } catch {
            throw CADAngleOracleError.mismatch(
                "The immutable angle source snapshot could not be read: \(error)."
            )
        }
        guard source.counts.sketchCount == 2,
              source.counts.entityCount == 2,
              source.counts.regionCount == 0,
              source.sketches.count == 2,
              source.entries.count == 2,
              source.regions.isEmpty,
              source.sketches.allSatisfy({ $0.plane == sourcePlane && $0.entityCount == 1 }),
              let firstEntry = source.entries.first(where: { $0.sourceFeatureID == firstDescription }),
              let secondEntry = source.entries.first(where: { $0.sourceFeatureID == secondDescription }),
              firstEntry.entityKind == "line",
              secondEntry.entityKind == "line" else {
            throw CADAngleOracleError.mismatch(
                "The immutable source snapshot contains missing, extra, or substitute geometry."
            )
        }

        let firstObserved = try observedSegment(
            firstEntry,
            sourcePlane: sourcePlane,
            tolerance: tolerance,
            role: "first-line"
        )
        let secondObserved = try observedSegment(
            secondEntry,
            sourcePlane: sourcePlane,
            tolerance: tolerance,
            role: "second-line"
        )
        let intersection = expected.intersection.meters
        let expectedFirstEnd = endpoint(
            from: intersection,
            direction: expected.firstDirection,
            length: expected.firstLength.meters
        )
        let expectedSecondEnd = endpoint(
            from: intersection,
            direction: expected.secondDirection,
            length: expected.secondLength.meters
        )
        guard accepts(intersection, firstObserved.start, tolerance),
              accepts(intersection, secondObserved.start, tolerance),
              accepts(expectedFirstEnd, firstObserved.end, tolerance),
              accepts(expectedSecondEnd, secondObserved.end, tolerance),
              tolerance.acceptsLinear(
                  expected: expected.firstLength.meters,
                  observed: firstObserved.vector.length
              ),
              tolerance.acceptsLinear(
                  expected: expected.secondLength.meters,
                  observed: secondObserved.vector.length
              ) else {
            throw CADAngleOracleError.mismatch(
                "The angle intersection, endpoint order, direction, or segment length is wrong."
            )
        }

        let dot = firstObserved.vector.dot(secondObserved.vector)
            / (firstObserved.vector.length * secondObserved.vector.length)
        let observedAngle = acos(max(-1.0, min(1.0, dot)))
        guard tolerance.isNonDegenerate(firstObserved.vector.length),
              tolerance.isNonDegenerate(secondObserved.vector.length),
              observedAngle > 0.0,
              observedAngle < .pi,
              tolerance.acceptsAngle(
                  expected: expected.includedAngle.radians,
                  observed: observedAngle
              ),
              snapshot.evaluationSnapshot.bodyCount == 0 else {
            throw CADAngleOracleError.mismatch(
                "The normalized unsigned included angle or zero-body contract is wrong."
            )
        }

        return CADAngleOracleObservation(
            readCount: 1,
            entityCount: source.counts.entityCount,
            featureCount: graph.nodes.count,
            bodyCount: snapshot.evaluationSnapshot.bodyCount
        )
    }

    private static func isOneLine(_ feature: FeatureNode, on plane: SketchPlane) -> Bool {
        guard feature.isSuppressed == false,
              feature.outputs.contains(where: { $0.role == .curve }),
              case .sketch(let sketch) = feature.operation,
              sketch.plane == plane,
              sketch.entities.count == 1,
              let entity = sketch.entities.values.first,
              case .line = entity else {
            return false
        }
        return true
    }

    private static func observedSegment(
        _ entry: SketchEntitySummaryResult.EntityEntry,
        sourcePlane: SketchPlane,
        tolerance: CADBenchmarkTolerancePolicy,
        role: String
    ) throws -> (start: Point3D, end: Point3D, vector: Vector3D) {
        guard let localStart = entry.start,
              let localEnd = entry.end,
              localStart.x.isFinite,
              localStart.y.isFinite,
              localEnd.x.isFinite,
              localEnd.y.isFinite else {
            throw CADAngleOracleError.mismatch("The \(role) source has no finite endpoints.")
        }
        let start: Point3D
        let end: Point3D
        do {
            start = try CADAngleGeometryMapping.worldPoint(
                from: localStart,
                sourcePlane: sourcePlane,
                modelingTolerance: tolerance.modelingTolerance
            )
            end = try CADAngleGeometryMapping.worldPoint(
                from: localEnd,
                sourcePlane: sourcePlane,
                modelingTolerance: tolerance.modelingTolerance
            )
        } catch {
            throw CADAngleOracleError.mismatch(
                "The \(role) local endpoints could not be mapped to world space: \(error)."
            )
        }
        let vector = end - start
        guard tolerance.isNonDegenerate(vector.length) else {
            throw CADAngleOracleError.mismatch("The \(role) source is degenerate.")
        }
        return (start, end, vector)
    }

    private static func endpoint(
        from start: CADPoint3D,
        direction: CADDirection3D,
        length: Double
    ) -> CADPoint3D {
        let scale = length / direction.length
        return CADPoint3D(
            x: start.x + direction.x * scale,
            y: start.y + direction.y * scale,
            z: start.z + direction.z * scale,
            unit: .meter
        )
    }

    private static func accepts(
        _ expected: CADPoint3D,
        _ observed: Point3D,
        _ tolerance: CADBenchmarkTolerancePolicy
    ) -> Bool {
        tolerance.acceptsLinear(expected: expected.x, observed: observed.x)
            && tolerance.acceptsLinear(expected: expected.y, observed: observed.y)
            && tolerance.acceptsLinear(expected: expected.z, observed: observed.z)
    }
}
