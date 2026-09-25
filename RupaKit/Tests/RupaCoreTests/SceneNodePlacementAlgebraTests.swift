import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

/// Covers the arithmetic every placement command depends on.
///
/// Composition order and matrix layout are the two things that fail silently: a transposed matrix or
/// a reversed product still produces a placement, just the wrong one. Each test states the expected
/// result as a point the transform must map to, so a wrong convention cannot pass.
@Suite struct SceneNodePlacementAlgebraTests {
    private let tolerance = 1.0e-9

    private func quarterTurnAboutZ() throws -> Transform3D {
        try Transform3D.rotation(axis: .unitZ, angleRadians: .pi / 2.0)
    }

    @Test func compositionAppliesTheLeftTransformAfterTheRight() throws {
        let rotation = try quarterTurnAboutZ()
        let translation = try Transform3D.translation(Vector3D(x: 1.0, y: 0.0, z: 0.0))
        let start = Point3D(x: 1.0, y: 0.0, z: 0.0)

        // Rotating first lands on the Y axis and is then pushed along X; translating first moves
        // along X and the rotation carries the whole offset onto the Y axis.
        let rotateThenTranslate = try translation.composed(with: rotation).applied(to: start)
        let translateThenRotate = try rotation.composed(with: translation).applied(to: start)

        #expect(rotateThenTranslate.isApproximatelyEqual(
            to: Point3D(x: 1.0, y: 1.0, z: 0.0),
            tolerance: tolerance
        ))
        #expect(translateThenRotate.isApproximatelyEqual(
            to: Point3D(x: 0.0, y: 2.0, z: 0.0),
            tolerance: tolerance
        ))
    }

    @Test func translationLandsInTheRowMajorTranslationSlots() throws {
        let translation = try Transform3D.translation(Vector3D(x: 3.0, y: 5.0, z: 7.0))

        #expect(translation.matrix.values[3] == 3.0)
        #expect(translation.matrix.values[7] == 5.0)
        #expect(translation.matrix.values[11] == 7.0)
    }

    @Test func inverseUndoesTheTransform() throws {
        let placement = try Transform3D.translation(Vector3D(x: 2.0, y: -3.0, z: 4.0))
            .composed(with: try quarterTurnAboutZ())
        let start = Point3D(x: 1.5, y: 0.25, z: -2.0)

        let roundTrip = try placement.inverse().applied(to: placement.applied(to: start))
        let identity = try placement.composed(with: placement.inverse())

        #expect(roundTrip.isApproximatelyEqual(to: start, tolerance: tolerance))
        for (value, expected) in zip(identity.matrix.values, Matrix4x4.identity.values) {
            #expect(abs(value - expected) < tolerance)
        }
    }

    @Test func aFlattenedTransformCannotBeInverted() throws {
        var values = Matrix4x4.identity.values
        values[10] = 0.0
        let flattened = Transform3D(matrix: try Matrix4x4(values: values))

        #expect(throws: EditorError.self) {
            try flattened.inverse()
        }
    }

    @Test func rotationAboutAPivotLeavesThePivotWhereItIs() throws {
        let pivot = Point3D(x: 2.0, y: 1.0, z: 0.0)
        let rotation = try Transform3D.rotation(
            axis: .unitZ,
            angleRadians: .pi / 2.0,
            about: pivot
        )

        let heldPivot = try rotation.applied(to: pivot)
        let swungPoint = try rotation.applied(to: Point3D(x: 3.0, y: 1.0, z: 0.0))

        #expect(heldPivot.isApproximatelyEqual(to: pivot, tolerance: tolerance))
        #expect(swungPoint.isApproximatelyEqual(
            to: Point3D(x: 2.0, y: 2.0, z: 0.0),
            tolerance: tolerance
        ))
    }

@Test func axisScaleAndVectorMappingShareTheCheckedSceneTransform() throws {
        let scale = try Transform3D.scale(
            Vector3D(x: -2.0, y: 3.0, z: 4.0),
            about: Point3D(x: 1.0, y: 2.0, z: 3.0)
        )
        let mappedPoint = try scale.applied(to: Point3D(x: 2.0, y: 3.0, z: 4.0))
        let mappedVector = try scale.applyingLinearPart(to: Vector3D(x: 2.0, y: 3.0, z: 4.0))
        let restoredVector = try scale.inverseApplyingLinearPart(to: mappedVector)

        #expect(mappedPoint.isApproximatelyEqual(to: Point3D(x: -1.0, y: 5.0, z: 7.0), tolerance: tolerance))
        #expect(mappedVector == Vector3D(x: -4.0, y: 9.0, z: 16.0))
        #expect((restoredVector - Vector3D(x: 2.0, y: 3.0, z: 4.0)).length < tolerance)
    }

    @Test func affinePlacementValidationRejectsPerspectiveAndSingularMatrices() throws {
        let perspective = Transform3D(matrix: try Matrix4x4(values: [
            1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0.1, 0, 0, 1
        ]))
        let singular = Transform3D(matrix: try Matrix4x4(values: [
            1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1
        ]))

        #expect(throws: EditorError.self) { try perspective.validateAffinePlacement() }
        #expect(throws: EditorError.self) { try singular.validateAffinePlacement() }
    }

    @Test func aZeroLengthRotationAxisIsRejected() throws {
        #expect(throws: EditorError.self) {
            try Transform3D.rotation(axis: .zero, angleRadians: .pi)
        }
    }
}

@Test func planeNormalUsesInverseTransposeUnderNonUniformScale() throws {
    let scale = try Transform3D.scale(
        Vector3D(x: 2.0, y: 1.0, z: 0.5),
        about: .origin
    )
    let normal = try scale.applyingNormal(to: Vector3D(x: 1.0, y: 1.0, z: 0.0))
    let expected = try Vector3D(x: 0.5, y: 1.0, z: 0.0).normalized(tolerance: 1.0e-12)

    #expect((normal - expected).length < 1.0e-12)
}

/// Covers the tree walk that turns stored local transforms into world placements.
@Suite struct SceneNodeHierarchyTests {
    private let tolerance = 1.0e-9

    @Test func worldTransformAccumulatesEveryAncestorPlacement() throws {
        let fixture = try SceneNodeHierarchyFixture()
        let hierarchy = try SceneNodeHierarchy(metadata: fixture.metadata)

        let outer = try hierarchy.worldTransform(of: fixture.outerID).applied(to: .origin)
        let inner = try hierarchy.worldTransform(of: fixture.innerID).applied(to: .origin)

        #expect(outer.isApproximatelyEqual(to: Point3D(x: 1.0, y: 0.0, z: 0.0), tolerance: tolerance))
        #expect(inner.isApproximatelyEqual(to: Point3D(x: 1.0, y: 2.0, z: 0.0), tolerance: tolerance))
    }

    @Test func parentWorldTransformIsWhatALocalTransformIsRelativeTo() throws {
        let fixture = try SceneNodeHierarchyFixture()
        let hierarchy = try SceneNodeHierarchy(metadata: fixture.metadata)

        let parentWorld = try hierarchy.parentWorldTransform(of: fixture.innerID)
        let outerWorld = try hierarchy.worldTransform(of: fixture.outerID)

        #expect(parentWorld == outerWorld)
        #expect(try hierarchy.parentWorldTransform(of: fixture.rootID) == .identity)
    }

    @Test func outermostSelectionDropsNodesCarriedByTheirAncestors() throws {
        let fixture = try SceneNodeHierarchyFixture()
        let hierarchy = try SceneNodeHierarchy(metadata: fixture.metadata)

        let reduced = hierarchy.outermostSceneNodeIDs(
            among: [fixture.innerID, fixture.outerID, fixture.siblingID]
        )

        #expect(reduced == [fixture.outerID, fixture.siblingID])
    }

    @Test func nearestCommonAncestorIsTheDeepestNodeHoldingEveryMember() throws {
        let fixture = try SceneNodeHierarchyFixture()
        let hierarchy = try SceneNodeHierarchy(metadata: fixture.metadata)

        #expect(
            hierarchy.nearestCommonAncestorID(of: [fixture.outerID, fixture.siblingID])
                == fixture.rootID
        )
        #expect(
            hierarchy.nearestCommonAncestorID(of: [fixture.innerID])
                == fixture.outerID
        )
    }

    @Test func componentOccurrencesRetainIndependentPlacementAndRejectRecursion() throws {
        var fixture = try SceneNodeHierarchyFixture()
        let definition = ComponentDefinition(name: "Part", rootSceneNodeIDs: [fixture.innerID])
        let instance = ComponentInstance(
            definitionID: definition.id, name: "Copy",
            localTransform: try .translation(Vector3D(x: 0, y: 0, z: 3))
        )
        fixture.metadata.componentDefinitions[definition.id] = definition
        fixture.metadata.componentInstances[instance.id] = instance
        fixture.metadata.sceneNodes[fixture.siblingID]?.reference = .componentInstance(instance.id)
        let occurrences = try SceneNodeHierarchy(metadata: fixture.metadata).resolvedOccurrences()
        let copies = occurrences.filter { $0.sourceSceneNodeID == fixture.innerID }
        #expect(copies.count == 2)
        #expect(Set(copies.map(\.id)).count == 2)
        let copy = try #require(copies.first { $0.componentInstanceID == instance.id })
        #expect(copy.sceneNodeID == fixture.siblingID)
        #expect(try copy.worldTransform.applied(to: .origin).isApproximatelyEqual(
            to: Point3D(x: 0, y: 2, z: 3), tolerance: tolerance
        ))
        fixture.metadata.componentDefinitions[definition.id]?.rootSceneNodeIDs = [fixture.siblingID]
        #expect(throws: EditorError.self) {
            try SceneNodeHierarchy(metadata: fixture.metadata).resolvedOccurrences()
        }
    }

    @Test func aNodeClaimedByTwoParentsIsRejected() throws {
        var fixture = try SceneNodeHierarchyFixture()
        fixture.metadata.sceneNodes[fixture.siblingID]?.childIDs = [fixture.innerID]

        #expect(throws: EditorError.self) {
            try SceneNodeHierarchy(metadata: fixture.metadata)
        }
    }

    @Test func aNodeOutsideTheRootedTreeInvalidatesTheHierarchy() throws {
        var fixture = try SceneNodeHierarchyFixture()
        let strandedNode = SceneNode(name: "Stranded")
        fixture.metadata.sceneNodes[strandedNode.id] = strandedNode

        #expect(throws: EditorError.self) {
            try SceneNodeHierarchy(metadata: fixture.metadata)
        }
    }

    @Test func aNonAffineScenePlacementInvalidatesTheHierarchy() throws {
        var fixture = try SceneNodeHierarchyFixture()
        var values = Matrix4x4.identity.values
        values[12] = 0.1
        fixture.metadata.sceneNodes[fixture.outerID]?.localTransform = Transform3D(
            matrix: try Matrix4x4(values: values)
        )

        #expect(throws: EditorError.self) {
            try SceneNodeHierarchy(metadata: fixture.metadata)
        }
    }
}

/// A root holding an outer node offset along X, an inner node offset along Y inside it, and a
/// sibling of the outer node.
struct SceneNodeHierarchyFixture {
    var metadata: ProductMetadata
    let rootID: SceneNodeID
    let outerID: SceneNodeID
    let innerID: SceneNodeID
    let siblingID: SceneNodeID

    init() throws {
        let inner = SceneNode(
            name: "Inner",
            localTransform: try .translation(Vector3D(x: 0.0, y: 2.0, z: 0.0))
        )
        let outer = SceneNode(
            name: "Outer",
            childIDs: [inner.id],
            localTransform: try .translation(Vector3D(x: 1.0, y: 0.0, z: 0.0))
        )
        let sibling = SceneNode(name: "Sibling")
        let root = SceneNode(name: "Scene", childIDs: [outer.id, sibling.id])

        metadata = ProductMetadata(
            sceneNodes: [
                root.id: root,
                outer.id: outer,
                inner.id: inner,
                sibling.id: sibling
            ],
            rootSceneNodeIDs: [root.id]
        )
        rootID = root.id
        outerID = outer.id
        innerID = inner.id
        siblingID = sibling.id
    }
}
