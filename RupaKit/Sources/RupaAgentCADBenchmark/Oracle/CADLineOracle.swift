import Foundation
import RupaCore
import RupaKit
import SwiftCAD

enum CADLineOracleError: Error, Equatable, CustomStringConvertible {
    case mismatch(String)

    var description: String {
        switch self {
        case .mismatch(let reason):
            "Line oracle mismatch: \(reason)"
        }
    }
}

struct CADLineOracleObservation: Equatable, Sendable {
    let readCount: Int
    let entityCount: Int
    let featureCount: Int
    let bodyCount: Int
}

/// Exact source/B-Rep observation for an activated finite-line case.
enum CADLineOracle {
    static func evaluate(
        expected: CADLineChallengeInput,
        challenge: CADChallenge,
        bindings: CADOutputRoleBindings,
        stepResults: [CADCandidateStepResult],
        snapshot: ProjectViewSnapshot
    ) throws -> CADLineOracleObservation {
        let caseID = challenge.id
        guard CADActivatedLineCase(rawValue: caseID.rawValue) != nil,
              challenge.category == .line else {
            throw CADLineOracleError.mismatch(
                "The oracle received an inactive or non-line challenge."
            )
        }
        try CADChallengeGeometryValidator.validate(.line(expected), caseID: caseID)
        let publicProjection: CADLineChallengeProjection
        do {
            publicProjection = try CADLineChallengeProjection.decode(challenge)
        } catch {
            throw CADLineOracleError.mismatch(
                "The candidate-visible line challenge could not be decoded: \(error)."
            )
        }
        guard publicProjection.orientation == expected.plane,
              publicProjection.start.meters == expected.start.meters,
              publicProjection.end.meters == expected.end.meters,
              publicProjection.length.meters == expected.length.meters else {
            throw CADLineOracleError.mismatch(
                "The candidate-visible challenge and private line expectation disagree."
            )
        }
        try bindings.validate(for: challenge, availableStepResults: stepResults)

        guard bindings.bindings.count == 1,
              let binding = bindings.bindings.first,
              binding.role == "segment",
              let stepResult = stepResults.first(where: { $0.stepIndex == binding.stepIndex }) else {
            throw CADLineOracleError.mismatch(
                "The segment role is not bound to one candidate step."
            )
        }
        let featureIDDescription = try binding.selector.resolveFeatureID(
            from: stepResult,
            caseID: caseID,
            role: binding.role
        )
        guard let featureUUID = UUID(uuidString: featureIDDescription) else {
            throw CADLineOracleError.mismatch("The bound FeatureID is not a tagged UUID.")
        }
        let featureID = FeatureID(featureUUID)
        let document = snapshot.document.document
        let graph = document.cadDocument.designGraph
        let tolerance = try CADBenchmarkTolerancePolicy(
            modelingTolerance: document.modelingSettings.tolerance
        )
        let sourcePlane: SketchPlane
        do {
            sourcePlane = try CADLineGeometryMapping.sourcePlane(
                orientation: expected.plane,
                anchor: expected.start,
                modelingTolerance: tolerance.modelingTolerance,
                caseID: caseID
            )
        } catch {
            throw CADLineOracleError.mismatch(
                "The expected line source plane could not be constructed: \(error)."
            )
        }

        guard graph.order.count == 1,
              graph.nodes.count == 1,
              graph.order.first == featureID,
              let feature = graph.nodes[featureID],
              feature.isSuppressed == false,
              feature.outputs.contains(where: { $0.role == .curve }) else {
            throw CADLineOracleError.mismatch(
                "The bound feature is not the sole unsuppressed curve-owning source feature."
            )
        }
        guard case .sketch(let sketch) = feature.operation,
              sketch.plane == sourcePlane,
              sketch.entities.count == 1 else {
            throw CADLineOracleError.mismatch(
                "The bound source is not one sketch line on the canonical source plane."
            )
        }

        let sourceSnapshot: SketchEntitySnapshot
        do {
            sourceSnapshot = try SketchEntitySnapshotService().snapshot(
                document: document,
                objectRegistry: snapshot.objectRegistry
            )
        } catch {
            throw CADLineOracleError.mismatch(
                "The immutable source snapshot could not be read: \(error)."
            )
        }
        guard sourceSnapshot.counts.sketchCount == 1,
              sourceSnapshot.counts.entityCount == 1,
              sourceSnapshot.entries.count == 1,
              sourceSnapshot.sketches.count == 1,
              let entry = sourceSnapshot.entries.first,
              let sketchEntry = sourceSnapshot.sketches.first,
              entry.entityKind == "line",
              entry.sourceFeatureID == featureIDDescription,
              sketchEntry.sourceFeatureID == featureIDDescription,
              sketchEntry.plane == sourcePlane,
              sketchEntry.entityCount == 1 else {
            throw CADLineOracleError.mismatch(
                "The immutable source snapshot contains an unexpected sketch/entity shape."
            )
        }
        guard let observedStart = entry.start,
              let observedEnd = entry.end,
              observedStart.x.isFinite,
              observedStart.y.isFinite,
              observedEnd.x.isFinite,
              observedEnd.y.isFinite else {
            throw CADLineOracleError.mismatch("The line source snapshot has no finite endpoints.")
        }

        let observedStartWorld: Point3D
        let observedEndWorld: Point3D
        do {
            observedStartWorld = try CADLineGeometryMapping.worldPoint(
                from: observedStart,
                sourcePlane: sourcePlane,
                modelingTolerance: tolerance.modelingTolerance
            )
            observedEndWorld = try CADLineGeometryMapping.worldPoint(
                from: observedEnd,
                sourcePlane: sourcePlane,
                modelingTolerance: tolerance.modelingTolerance
            )
        } catch {
            throw CADLineOracleError.mismatch(
                "The source local endpoints could not be mapped to world space: \(error)."
            )
        }
        let expectedStart = expected.start.meters
        let expectedEnd = expected.end.meters
        guard accepts(
            expected: expectedStart,
            observed: observedStartWorld,
            tolerance: tolerance
        ),
        accepts(
            expected: expectedEnd,
            observed: observedEndWorld,
            tolerance: tolerance
        ) else {
            throw CADLineOracleError.mismatch(
                "The source endpoint orientation or world coordinates are wrong."
            )
        }

        let expectedStartWorld = Point3D(
            x: expectedStart.x,
            y: expectedStart.y,
            z: expectedStart.z
        )
        let expectedEndWorld = Point3D(
            x: expectedEnd.x,
            y: expectedEnd.y,
            z: expectedEnd.z
        )
        guard abs(sourcePlane.mapNormalDistance(to: expectedStartWorld))
            <= tolerance.modelingTolerance.distance,
        abs(sourcePlane.mapNormalDistance(to: expectedEndWorld))
            <= tolerance.modelingTolerance.distance else {
            throw CADLineOracleError.mismatch("The expected line endpoints are outside its source plane.")
        }

        let observedDelta = observedEndWorld - observedStartWorld
        let observedLength = observedDelta.length
        guard tolerance.isNonDegenerate(observedLength),
              tolerance.isNonDegenerate(expected.length.meters),
              tolerance.acceptsLinear(
                  expected: expected.length.meters,
                  observed: observedLength
              ) else {
            throw CADLineOracleError.mismatch("The source line length or non-degeneracy is wrong.")
        }
        guard snapshot.evaluationSnapshot.bodyCount == 0 else {
            throw CADLineOracleError.mismatch(
                "A line case must leave zero evaluated bodies."
            )
        }

        return CADLineOracleObservation(
            readCount: 1,
            entityCount: sourceSnapshot.counts.entityCount,
            featureCount: graph.nodes.count,
            bodyCount: snapshot.evaluationSnapshot.bodyCount
        )
    }

    private static func accepts(
        expected: CADPoint3D,
        observed: Point3D,
        tolerance: CADBenchmarkTolerancePolicy
    ) -> Bool {
        tolerance.acceptsLinear(expected: expected.x, observed: observed.x)
            && tolerance.acceptsLinear(expected: expected.y, observed: observed.y)
            && tolerance.acceptsLinear(expected: expected.z, observed: observed.z)
    }
}

private extension SketchPlane {
    func mapNormalDistance(to point: Point3D) -> Double {
        switch self {
        case .xy:
            return point.z
        case .yz:
            return point.x
        case .zx:
            return point.y
        case .plane(let plane):
            let delta = point - plane.origin
            return delta.dot(plane.normal)
        }
    }
}
