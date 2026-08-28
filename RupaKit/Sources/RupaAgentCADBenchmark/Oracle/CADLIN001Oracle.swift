import Foundation
import RupaCore
import RupaKit
import SwiftCAD

enum CADLIN001OracleError: Error, Equatable, CustomStringConvertible {
    case mismatch(String)

    var description: String {
        switch self {
        case .mismatch(let reason):
            "LIN-001 oracle mismatch: \(reason)"
        }
    }
}

struct CADLIN001OracleObservation: Equatable, Sendable {
    let readCount: Int
    let entityCount: Int
    let featureCount: Int
    let bodyCount: Int
}

enum CADLIN001Oracle {
    static func evaluate(
        expected: CADLineChallengeInput,
        challenge: CADChallenge,
        bindings: CADOutputRoleBindings,
        stepResults: [CADCandidateStepResult],
        snapshot: ProjectViewSnapshot
    ) throws -> CADLIN001OracleObservation {
        let caseID: CADBenchmarkCaseID = "LIN-001"
        guard challenge.id == caseID, challenge.category == .line else {
            throw CADLIN001OracleError.mismatch("The oracle received a non-LIN-001 challenge.")
        }
        try CADChallengeGeometryValidator.validate(.line(expected), caseID: caseID)
        try bindings.validate(for: challenge, availableStepResults: stepResults)

        guard bindings.bindings.count == 1,
              let binding = bindings.bindings.first,
              binding.role == "segment",
              let stepResult = stepResults.first(where: { $0.stepIndex == binding.stepIndex }) else {
            throw CADLIN001OracleError.mismatch("The segment role is not bound to one candidate step.")
        }
        let featureIDDescription = try binding.selector.resolveFeatureID(
            from: stepResult,
            caseID: caseID,
            role: binding.role
        )
        guard let featureUUID = UUID(uuidString: featureIDDescription) else {
            throw CADLIN001OracleError.mismatch("The bound FeatureID is not a tagged UUID.")
        }
        let featureID = FeatureID(featureUUID)
        let document = snapshot.document.document
        let graph = document.cadDocument.designGraph
        guard graph.order.count == 1,
              graph.nodes.count == 1,
              graph.order.first == featureID,
              let feature = graph.nodes[featureID],
              feature.isSuppressed == false,
              feature.outputs.contains(where: { $0.role == .curve }) else {
            throw CADLIN001OracleError.mismatch(
                "The bound feature is not the sole unsuppressed curve-owning source feature."
            )
        }
        guard case .sketch(let sketch) = feature.operation,
              sketch.plane == .xy,
              sketch.entities.count == 1 else {
            throw CADLIN001OracleError.mismatch("The bound source is not one XY sketch line.")
        }

        let sourceSnapshot = try SketchEntitySnapshotService().snapshot(
            document: document,
            objectRegistry: snapshot.objectRegistry
        )
        guard sourceSnapshot.counts.sketchCount == 1,
              sourceSnapshot.counts.entityCount == 1,
              sourceSnapshot.entries.count == 1,
              sourceSnapshot.sketches.count == 1,
              let entry = sourceSnapshot.entries.first,
              let sketchEntry = sourceSnapshot.sketches.first,
              entry.entityKind == "line",
              entry.sourceFeatureID == featureIDDescription,
              sketchEntry.sourceFeatureID == featureIDDescription,
              sketchEntry.plane == .xy,
              sketchEntry.entityCount == 1 else {
            throw CADLIN001OracleError.mismatch(
                "The immutable source snapshot contains an unexpected sketch/entity shape."
            )
        }
        guard let observedStart = entry.start,
              let observedEnd = entry.end else {
            throw CADLIN001OracleError.mismatch("The line source snapshot has no endpoints.")
        }

        let tolerance = try CADBenchmarkTolerancePolicy(
            modelingTolerance: document.modelingSettings.tolerance
        )
        let expectedStart = expected.start.meters
        let expectedEnd = expected.end.meters
        let observedStartPoint = CADPoint3D(
            x: observedStart.x,
            y: observedStart.y,
            z: 0.0,
            unit: .meter
        )
        let observedEndPoint = CADPoint3D(
            x: observedEnd.x,
            y: observedEnd.y,
            z: 0.0,
            unit: .meter
        )
        guard tolerance.acceptsLinear(expected: expectedStart.x, observed: observedStart.x),
              tolerance.acceptsLinear(expected: expectedStart.y, observed: observedStart.y),
              tolerance.acceptsLinear(expected: expectedEnd.x, observed: observedEnd.x),
              tolerance.acceptsLinear(expected: expectedEnd.y, observed: observedEnd.y) else {
            throw CADLIN001OracleError.mismatch("The source endpoint orientation or coordinates are wrong.")
        }

        let frame = expected.plane.frame(anchor: expected.start)
        guard abs(frame.signedNormalDistance(to: observedStartPoint)) <= tolerance.modelingTolerance.distance,
              abs(frame.signedNormalDistance(to: observedEndPoint)) <= tolerance.modelingTolerance.distance else {
            throw CADLIN001OracleError.mismatch("The source endpoints are outside the expected affine plane.")
        }

        let observedLength = hypot(
            observedEnd.x - observedStart.x,
            observedEnd.y - observedStart.y
        )
        guard tolerance.isNonDegenerate(observedLength),
              tolerance.isNonDegenerate(expected.length.meters),
              tolerance.acceptsLinear(expected: expected.length.meters, observed: observedLength) else {
            throw CADLIN001OracleError.mismatch("The source line length or non-degeneracy is wrong.")
        }

        return CADLIN001OracleObservation(
            readCount: 1,
            entityCount: sourceSnapshot.counts.entityCount,
            featureCount: graph.nodes.count,
            bodyCount: snapshot.evaluationSnapshot.bodyCount
        )
    }
}
