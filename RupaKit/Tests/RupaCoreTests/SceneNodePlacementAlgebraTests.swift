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

    @Test func translationLandsInTheColumnMajorTranslationSlots() throws {
        let translation = try Transform3D.translation(Vector3D(x: 3.0, y: 5.0, z: 7.0))

        #expect(translation.matrix.values[12] == 3.0)
        #expect(translation.matrix.values[13] == 5.0)
        #expect(translation.matrix.values[14] == 7.0)
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

    @Test func aZeroLengthRotationAxisIsRejected() throws {
        #expect(throws: EditorError.self) {
            try Transform3D.rotation(axis: .zero, angleRadians: .pi)
        }
    }
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

    @Test func aNodeClaimedByTwoParentsIsRejected() throws {
        var fixture = try SceneNodeHierarchyFixture()
        fixture.metadata.sceneNodes[fixture.siblingID]?.childIDs = [fixture.innerID]

        #expect(throws: EditorError.self) {
            try SceneNodeHierarchy(metadata: fixture.metadata)
        }
    }

    @Test func aNodeOutsideTheRootedTreeHasNoWorldPlacement() throws {
        var fixture = try SceneNodeHierarchyFixture()
        let strandedNode = SceneNode(name: "Stranded")
        fixture.metadata.sceneNodes[strandedNode.id] = strandedNode
        let hierarchy = try SceneNodeHierarchy(metadata: fixture.metadata)

        #expect(throws: EditorError.self) {
            try hierarchy.worldTransform(of: strandedNode.id)
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
