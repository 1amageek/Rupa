import Foundation
import RupaCore
import RupaCoreTypes
import RupaGeometry
import RupaKit

enum CADTransformOracleError: Error, Equatable, CustomStringConvertible {
    case mismatch(String)

    var description: String {
        switch self {
        case .mismatch(let reason):
            "Transform oracle mismatch: \(reason)"
        }
    }
}

struct CADTransformOracleObservation: Equatable, Sendable {
    let readCount: Int
    let featureCount: Int
    let sceneNodeCount: Int
    let bodyCount: Int
}

/// Proves that the seeded source is unchanged and only its requested placement changed.
enum CADTransformOracle {
    static func evaluate(
        expected: CADTransformChallengeInput,
        challenge: CADChallenge,
        sceneNodeID: SceneNodeID,
        expectedTransform: Transform3D,
        initial: ProjectViewSnapshot,
        final: ProjectViewSnapshot
    ) throws -> CADTransformOracleObservation {
        let projection = try CADTransformChallengeProjection.decode(challenge)
        guard matches(projection, expected: expected) else {
            throw CADTransformOracleError.mismatch(
                "The candidate-visible challenge and private transform expectation disagree."
            )
        }
        let oracleTransform = try CADTransformGeometryMapping.localTransform(
            submission: CADTransformSubmission(
                translation: expected.translation,
                axisPoint: expected.axisPoint,
                rotationAxis: expected.rotationAxis,
                rotation: expected.rotation
            ),
            caseID: challenge.id
        )
        guard expectedTransform == oracleTransform else {
            throw CADTransformOracleError.mismatch(
                "The published local transform differs from the private target."
            )
        }
        let initialDocument = initial.document.document
        let finalDocument = final.document.document
        let initialSourceObservation = try CADTransformInitialSourceOracle.evaluate(
            expected: expected.source,
            caseID: challenge.id,
            sceneNodeID: sceneNodeID,
            snapshot: initial
        )
        try validateSourceAndLocalPlacement(
            initial: initialDocument,
            final: finalDocument,
            sceneNodeID: sceneNodeID,
            expectedTransform: oracleTransform
        )
        guard let initialNode = initialDocument.productMetadata.sceneNodes[sceneNodeID] else {
            throw CADTransformOracleError.mismatch("The initial source node is missing.")
        }

        let expectedWorld = try worldTransform(
            for: sceneNodeID,
            in: finalDocument.productMetadata,
            localTransform: oracleTransform
        )
        let occurrenceID = SceneOccurrenceID(rawValue: "scene.\(sceneNodeID.description)")
        if let evaluated = final.viewport.items.first(where: { $0.id == occurrenceID }) {
            guard evaluated.worldTransform == expectedWorld else {
                throw CADTransformOracleError.mismatch(
                    "World placement does not equal parent-times-local composition."
                )
            }
        } else if initialNode.reference?.kind == .body {
            throw CADTransformOracleError.mismatch(
                "The transformed body has no evaluated world occurrence."
            )
        }
        return CADTransformOracleObservation(
            readCount: initialSourceObservation.readCount,
            featureCount: finalDocument.cadDocument.designGraph.nodes.count,
            sceneNodeCount: authoredSceneNodeCount(in: finalDocument.productMetadata),
            bodyCount: final.evaluationSnapshot.bodyCount
        )
    }

    /// Counts authored scene nodes while excluding the document's structural roots.
    /// Root nodes are runtime scaffolding and are not candidate-authored geometry.
    static func authoredSceneNodeCount(in metadata: ProductMetadata) -> Int {
        let rootIDs = Set(metadata.rootSceneNodeIDs)
        return metadata.sceneNodes.keys.reduce(into: 0) { count, id in
            if rootIDs.contains(id) == false {
                count += 1
            }
        }
    }

    static func validateSourceAndLocalPlacement(
        initial: DesignDocument,
        final: DesignDocument,
        sceneNodeID: SceneNodeID,
        expectedTransform: Transform3D
    ) throws {
        guard try canonicalData(initial.cadDocument) == canonicalData(final.cadDocument) else {
            throw CADTransformOracleError.mismatch(
                "The transform changed source CAD identity or geometry."
            )
        }
        guard let initialNode = initial.productMetadata.sceneNodes[sceneNodeID],
              let finalNode = final.productMetadata.sceneNodes[sceneNodeID],
              initialNode.localTransform == .identity,
              finalNode.localTransform == expectedTransform,
              initialNode.reference == finalNode.reference else {
            throw CADTransformOracleError.mismatch(
                "The selected source node is missing, substituted, or incorrectly transformed."
            )
        }
        var normalizedFinalMetadata = final.productMetadata
        normalizedFinalMetadata.sceneNodes[sceneNodeID]?.localTransform = initialNode.localTransform
        guard normalizedFinalMetadata == initial.productMetadata else {
            throw CADTransformOracleError.mismatch(
                "The transform added, removed, or modified unrelated product metadata."
            )
        }
    }

    static func parentTimesLocal(
        parent: GeometryTransform3D,
        local: Transform3D
    ) throws -> GeometryTransform3D {
        try parent.multiplied(by: GeometryTransform3D(values: local.matrix.values))
    }

    private static func worldTransform(
        for sceneNodeID: SceneNodeID,
        in metadata: ProductMetadata,
        localTransform: Transform3D
    ) throws -> GeometryTransform3D {
        var parentByChild: [SceneNodeID: SceneNodeID] = [:]
        for parent in metadata.sceneNodes.values {
            for childID in parent.childIDs {
                guard parentByChild.updateValue(parent.id, forKey: childID) == nil else {
                    throw CADTransformOracleError.mismatch(
                        "The transformed source has multiple parents."
                    )
                }
            }
        }
        var parentIDs: [SceneNodeID] = []
        var visited: Set<SceneNodeID> = [sceneNodeID]
        var cursor = sceneNodeID
        while let parentID = parentByChild[cursor] {
            guard visited.insert(parentID).inserted else {
                throw CADTransformOracleError.mismatch(
                    "The transformed source hierarchy contains a cycle."
                )
            }
            parentIDs.append(parentID)
            cursor = parentID
        }
        var world = GeometryTransform3D.identity
        for parentID in parentIDs.reversed() {
            guard let parent = metadata.sceneNodes[parentID] else {
                throw CADTransformOracleError.mismatch(
                    "The transformed source parent is missing."
                )
            }
            world = try world.multiplied(by: GeometryTransform3D(
                values: parent.localTransform.matrix.values
            ))
        }
        return try parentTimesLocal(parent: world, local: localTransform)
    }

    private static func canonicalData<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    private static func matches(
        _ projection: CADTransformChallengeProjection,
        expected: CADTransformChallengeInput
    ) -> Bool {
        guard projection.translation.meters == expected.translation.meters,
              projection.axisPoint.meters == expected.axisPoint.meters,
              projection.rotationAxis == expected.rotationAxis,
              projection.rotation.radians == expected.rotation.radians else {
            return false
        }
        switch (projection.source, expected.source) {
        case let (.line(lhs), .line(rhs)):
            return lhs.orientation == rhs.plane
                && lhs.start.meters == rhs.start.meters
                && lhs.end.meters == rhs.end.meters
        case let (.rectangle(lhs), .rectangle(rhs)):
            return lhs.orientation == rhs.plane
                && lhs.center.meters == rhs.center.meters
                && lhs.width.meters == rhs.width.meters
                && lhs.height.meters == rhs.height.meters
        case let (.circle(lhs), .circle(rhs)):
            return lhs.orientation == rhs.plane
                && lhs.center.meters == rhs.center.meters
                && lhs.radius.meters == rhs.radius.meters
        case let (.box(lhs), .box(rhs)):
            return lhs.origin.meters == rhs.origin.meters
                && lhs.width.meters == rhs.width.meters
                && lhs.depth.meters == rhs.depth.meters
                && lhs.height.meters == rhs.height.meters
        case let (.cylinder(lhs), .cylinder(rhs)):
            return lhs.baseCenter.meters == rhs.baseCenter.meters
                && lhs.axis == rhs.axis
                && lhs.radius.meters == rhs.radius.meters
                && lhs.depth.meters == rhs.depth.meters
        default:
            return false
        }
    }
}
