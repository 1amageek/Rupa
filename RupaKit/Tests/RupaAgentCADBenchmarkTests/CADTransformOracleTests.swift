import RupaCore
import RupaGeometry
import SwiftCAD
import Testing
@testable import RupaAgentCADBenchmark

struct CADTransformOracleTests {
    @MainActor
    @Test
    func preservationOracleRejectsMissingExtraSubstitutedAndMutatedSources() throws {
        let challenge = try CADTransformPreparedCase.transform001.catalogEntry.challenge
        let projection = try CADTransformChallengeProjection.decode(challenge)
        let seed = try CADTransformGeometryMapping.seed(projection: projection)
        let submission = try CADTransformReferenceCandidate().submission(for: challenge)
        let transform = try CADTransformGeometryMapping.localTransform(
            submission: submission,
            caseID: projection.id
        )
        var valid = seed.document
        try valid.setSceneNodeTransform(id: seed.sceneNodeID, localTransform: transform)
        try CADTransformOracle.validateSourceAndLocalPlacement(
            initial: seed.document,
            final: valid,
            sceneNodeID: seed.sceneNodeID,
            expectedTransform: transform
        )

        var missing = valid
        missing.productMetadata.sceneNodes.removeValue(forKey: seed.sceneNodeID)
        #expect(throws: CADTransformOracleError.self) {
            try CADTransformOracle.validateSourceAndLocalPlacement(
                initial: seed.document,
                final: missing,
                sceneNodeID: seed.sceneNodeID,
                expectedTransform: transform
            )
        }

        var extra = valid
        let extraNode = SceneNode(name: "unexpected")
        extra.productMetadata.sceneNodes[extraNode.id] = extraNode
        extra.productMetadata.rootSceneNodeIDs.append(extraNode.id)
        #expect(throws: CADTransformOracleError.self) {
            try CADTransformOracle.validateSourceAndLocalPlacement(
                initial: seed.document,
                final: extra,
                sceneNodeID: seed.sceneNodeID,
                expectedTransform: transform
            )
        }

        var substituted = valid
        substituted.productMetadata.sceneNodes[seed.sceneNodeID]?.reference = nil
        #expect(throws: CADTransformOracleError.self) {
            try CADTransformOracle.validateSourceAndLocalPlacement(
                initial: seed.document,
                final: substituted,
                sceneNodeID: seed.sceneNodeID,
                expectedTransform: transform
            )
        }

        var mutated = valid
        _ = try mutated.createLineSketch(
            name: "unexpected geometry",
            plane: .xy,
            start: SketchPoint(
                x: .length(0, .millimeter),
                y: .length(0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(1, .millimeter),
                y: .length(0, .millimeter)
            )
        )
        #expect(throws: CADTransformOracleError.self) {
            try CADTransformOracle.validateSourceAndLocalPlacement(
                initial: seed.document,
                final: mutated,
                sceneNodeID: seed.sceneNodeID,
                expectedTransform: transform
            )
        }
    }

    @Test
    func axisPointCompositionAndParentTimesLocalUseColumnVectorOrder() throws {
        let submission = CADTransformSubmission(
            translation: CADPoint3D(x: 25, y: 0, z: 0),
            axisPoint: CADPoint3D(x: 50, y: 0, z: 0),
            rotationAxis: CADDirection3D(x: 0, y: 0, z: 1),
            rotation: CADAngle(value: 90)
        )
        let local = try CADTransformGeometryMapping.localTransform(
            submission: submission,
            caseID: "TRN-001"
        )
        let localGeometry = try GeometryTransform3D(values: local.matrix.values)
        let rotatedPivot = try localGeometry.applying(
            to: GeometryPoint3D(x: 0.05, y: 0, z: 0)
        )
        #expect(abs(rotatedPivot.x - 0.075) < 1e-12)
        #expect(abs(rotatedPivot.y) < 1e-12)
        #expect(abs(rotatedPivot.z) < 1e-12)

        let parent = try GeometryTransform3D(values: [
            1, 0, 0, 1,
            0, 1, 0, 2,
            0, 0, 1, 3,
            0, 0, 0, 1,
        ])
        let composed = try CADTransformOracle.parentTimesLocal(
            parent: parent,
            local: local
        )
        let expected = try parent.multiplied(by: localGeometry)
        #expect(composed == expected)
    }
}
