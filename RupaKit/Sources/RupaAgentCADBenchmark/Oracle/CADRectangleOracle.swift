import Foundation
import RupaCore
import RupaKit
import SwiftCAD

enum CADRectangleOracleError: Error, Equatable, CustomStringConvertible {
    case mismatch(String)

    var description: String {
        switch self {
        case .mismatch(let reason):
            "Rectangle oracle mismatch: \(reason)"
        }
    }
}

struct CADRectangleOracleObservation: Equatable, Sendable {
    let readCount: Int
    let entityCount: Int
    let featureCount: Int
    let bodyCount: Int
}

/// Exact source observation for an activated centered-rectangle case.
enum CADRectangleOracle {
    private struct LocalPoint: Equatable {
        let x: Double
        let y: Double
    }

    private struct LocalEdge {
        let start: LocalPoint
        let end: LocalPoint
    }

    static func evaluate(
        expected: CADRectangleChallengeInput,
        challenge: CADChallenge,
        bindings: CADOutputRoleBindings,
        stepResults: [CADCandidateStepResult],
        snapshot: ProjectViewSnapshot
    ) throws -> CADRectangleOracleObservation {
        let caseID = challenge.id
        guard CADActivatedRectangleCase(rawValue: caseID.rawValue) != nil,
              challenge.category == .rectangle else {
            throw CADRectangleOracleError.mismatch(
                "The oracle received an inactive or non-rectangle challenge."
            )
        }
        try CADChallengeGeometryValidator.validate(.rectangle(expected), caseID: caseID)
        let projection: CADRectangleChallengeProjection
        do {
            projection = try CADRectangleChallengeProjection.decode(challenge)
        } catch {
            throw CADRectangleOracleError.mismatch(
                "The candidate-visible rectangle challenge could not be decoded: \(error)."
            )
        }
        guard projection.orientation == expected.plane,
              projection.center.meters == expected.center.meters,
              projection.width.meters == expected.width.meters,
              projection.height.meters == expected.height.meters else {
            throw CADRectangleOracleError.mismatch(
                "The candidate-visible challenge and private rectangle expectation disagree."
            )
        }
        try bindings.validate(for: challenge, availableStepResults: stepResults)
        guard bindings.bindings.count == 1,
              let binding = bindings.bindings.first,
              binding.role == "rectangle",
              let stepResult = stepResults.first(where: { $0.stepIndex == binding.stepIndex }) else {
            throw CADRectangleOracleError.mismatch(
                "The rectangle role is not bound to one candidate step."
            )
        }
        let featureIDDescription = try binding.selector.resolveFeatureID(
            from: stepResult,
            caseID: caseID,
            role: binding.role
        )
        guard let featureUUID = UUID(uuidString: featureIDDescription) else {
            throw CADRectangleOracleError.mismatch("The bound FeatureID is not a tagged UUID.")
        }

        let featureID = FeatureID(featureUUID)
        let document = snapshot.document.document
        let graph = document.cadDocument.designGraph
        let tolerance = try CADBenchmarkTolerancePolicy(
            modelingTolerance: document.modelingSettings.tolerance
        )
        let sourcePlane: SketchPlane
        do {
            sourcePlane = try CADRectangleGeometryMapping.sourcePlane(
                orientation: expected.plane,
                targetCenter: expected.center,
                submittedCenter: expected.center,
                modelingTolerance: tolerance.modelingTolerance,
                caseID: caseID
            )
        } catch {
            throw CADRectangleOracleError.mismatch(
                "The expected rectangle plane could not be constructed: \(error)."
            )
        }

        guard graph.order.count == 1,
              graph.nodes.count == 1,
              graph.order.first == featureID,
              let feature = graph.nodes[featureID],
              feature.isSuppressed == false,
              feature.outputs.contains(where: { $0.role == .profile }) else {
            throw CADRectangleOracleError.mismatch(
                "The bound feature is not the sole unsuppressed profile source."
            )
        }
        guard case .sketch(let sketch) = feature.operation,
              sketch.plane == sourcePlane,
              sketch.entities.count == 4 else {
            throw CADRectangleOracleError.mismatch(
                "The bound source is not a four-line rectangle on the expected plane."
            )
        }

        let source = try SketchEntitySnapshotService().snapshot(
            document: document,
            objectRegistry: snapshot.objectRegistry
        )
        guard source.counts.sketchCount == 1,
              source.counts.entityCount == 4,
              source.counts.regionCount == 1,
              source.entries.count == 4,
              source.sketches.count == 1,
              source.regions.count == 1,
              let sketchEntry = source.sketches.first,
              let region = source.regions.first,
              sketchEntry.sourceFeatureID == featureIDDescription,
              sketchEntry.plane == sourcePlane,
              sketchEntry.entityCount == 4,
              region.sourceFeatureID == featureIDDescription,
              region.plane == sourcePlane,
              region.boundaryPointCount == 4,
              region.boundarySegmentCount == 4 else {
            throw CADRectangleOracleError.mismatch(
                "The source snapshot is not one closed four-edge rectangle region."
            )
        }
        guard source.entries.allSatisfy({
            $0.sourceFeatureID == featureIDDescription
                && $0.entityKind == "line"
                && $0.start != nil
                && $0.end != nil
        }) else {
            throw CADRectangleOracleError.mismatch(
                "The rectangle source contains a missing or non-line edge."
            )
        }

        let halfWidth = expected.width.meters / 2.0
        let halfHeight = expected.height.meters / 2.0
        let bottomLeft = LocalPoint(x: -halfWidth, y: -halfHeight)
        let bottomRight = LocalPoint(x: halfWidth, y: -halfHeight)
        let topRight = LocalPoint(x: halfWidth, y: halfHeight)
        let topLeft = LocalPoint(x: -halfWidth, y: halfHeight)
        var remaining = [
            LocalEdge(start: bottomLeft, end: bottomRight),
            LocalEdge(start: bottomRight, end: topRight),
            LocalEdge(start: topRight, end: topLeft),
            LocalEdge(start: topLeft, end: bottomLeft),
        ]
        for entry in source.entries {
            guard let start = entry.start,
                  let end = entry.end else {
                throw CADRectangleOracleError.mismatch("A rectangle edge has no endpoints.")
            }
            let observed = LocalEdge(
                start: LocalPoint(x: start.x, y: start.y),
                end: LocalPoint(x: end.x, y: end.y)
            )
            guard let index = remaining.firstIndex(where: {
                edge($0, matches: observed, tolerance: tolerance)
            }) else {
                throw CADRectangleOracleError.mismatch(
                    "A source edge does not match the expected width, height, or closure."
                )
            }
            remaining.remove(at: index)
        }
        guard remaining.isEmpty,
              tolerance.acceptsLinear(expected: 0.0, observed: region.center.x),
              tolerance.acceptsLinear(expected: 0.0, observed: region.center.y),
              region.boundaryPoints.count == 4,
              acceptsArea(
                  expected: expected.width.meters * expected.height.meters,
                  observed: region.areaSquareMeters,
                  width: expected.width.meters,
                  height: expected.height.meters,
                  tolerance: tolerance.modelingTolerance
              ),
              snapshot.evaluationSnapshot.bodyCount == 0 else {
            throw CADRectangleOracleError.mismatch(
                "The rectangle region center, area, boundary, or zero-body contract is wrong."
            )
        }

        return CADRectangleOracleObservation(
            readCount: 1,
            entityCount: source.counts.entityCount,
            featureCount: graph.nodes.count,
            bodyCount: snapshot.evaluationSnapshot.bodyCount
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
}
