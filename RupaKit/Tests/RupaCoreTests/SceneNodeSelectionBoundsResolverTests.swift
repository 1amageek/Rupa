import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

/// Covers the measurement a rotation pivot is taken from.
///
/// Body snapshots are stated in the geometry's own coordinates, so a resolver that forgets the
/// scene placement still returns a plausible box — just one centred on the wrong place. Each test
/// puts the geometry somewhere the source coordinates do not reach.
@Suite struct SceneNodeSelectionBoundsResolverTests {
    private let tolerance = 1.0e-9

    @Test func boundsAreMeasuredWhereTheSceneTreePutsTheBody() throws {
        let fixture = try SceneNodeBodyFixture()
        let hierarchy = try SceneNodeHierarchy(metadata: fixture.metadata)

        let bounds = try SceneNodeSelectionBoundsResolver().worldBounds(
            of: [fixture.leftID],
            hierarchy: hierarchy,
            bodySnapshots: fixture.bodySnapshots
        )

        // The unit cube sits at the origin in its own coordinates and is placed four metres out.
        #expect(bounds.minimum.isApproximatelyEqual(
            to: Point3D(x: 4.0, y: 0.0, z: 0.0),
            tolerance: tolerance
        ))
        #expect(bounds.maximum.isApproximatelyEqual(
            to: Point3D(x: 5.0, y: 1.0, z: 1.0),
            tolerance: tolerance
        ))
    }

    @Test func aParentPlacementCarriesIntoItsChildrensBounds() throws {
        let fixture = try SceneNodeBodyFixture()
        let hierarchy = try SceneNodeHierarchy(metadata: fixture.metadata)

        let bounds = try SceneNodeSelectionBoundsResolver().worldBounds(
            of: [fixture.groupID],
            hierarchy: hierarchy,
            bodySnapshots: fixture.bodySnapshots
        )

        // The group is lifted a metre, and holds a body one metre further out than the left body.
        #expect(bounds.minimum.isApproximatelyEqual(
            to: Point3D(x: 5.0, y: 1.0, z: 0.0),
            tolerance: tolerance
        ))
        #expect(bounds.maximum.isApproximatelyEqual(
            to: Point3D(x: 6.0, y: 2.0, z: 1.0),
            tolerance: tolerance
        ))
    }

    @Test func centreOfSeveralSelectedNodesLiesBetweenThem() throws {
        let fixture = try SceneNodeBodyFixture()
        let hierarchy = try SceneNodeHierarchy(metadata: fixture.metadata)

        let centre = try SceneNodeSelectionBoundsResolver().worldCenter(
            of: [fixture.leftID, fixture.groupID],
            hierarchy: hierarchy,
            bodySnapshots: fixture.bodySnapshots
        )

        #expect(centre.isApproximatelyEqual(
            to: Point3D(x: 5.0, y: 1.0, z: 0.5),
            tolerance: tolerance
        ))
    }

    @Test func aRotatedPlacementIsMeasuredFromEveryCorner() throws {
        var fixture = try SceneNodeBodyFixture()
        fixture.metadata.sceneNodes[fixture.leftID]?.localTransform = try .rotation(
            axis: .unitZ,
            angleRadians: .pi / 2.0
        )
        let hierarchy = try SceneNodeHierarchy(metadata: fixture.metadata)

        let bounds = try SceneNodeSelectionBoundsResolver().worldBounds(
            of: [fixture.leftID],
            hierarchy: hierarchy,
            bodySnapshots: fixture.bodySnapshots
        )

        // A quarter turn about Z swings the unit cube's X extent onto Y and its Y extent onto -X.
        #expect(bounds.minimum.isApproximatelyEqual(
            to: Point3D(x: -1.0, y: 0.0, z: 0.0),
            tolerance: tolerance
        ))
        #expect(bounds.maximum.isApproximatelyEqual(
            to: Point3D(x: 0.0, y: 1.0, z: 1.0),
            tolerance: tolerance
        ))
    }

    @Test func aSelectionWithoutGeometryIsRejectedRatherThanCentredOnTheOrigin() throws {
        let fixture = try SceneNodeBodyFixture()
        let hierarchy = try SceneNodeHierarchy(metadata: fixture.metadata)

        #expect(throws: EditorError.self) {
            try SceneNodeSelectionBoundsResolver().worldBounds(
                of: [fixture.emptyID],
                hierarchy: hierarchy,
                bodySnapshots: fixture.bodySnapshots
            )
        }
    }
}

@Suite struct SceneNodeNameAllocatorTests {
    @Test func aFreeNameIsUsedAsGiven() throws {
        let fixture = try SceneNodeBodyFixture()

        #expect(
            SceneNodeNameAllocator().uniqueName(base: "Group", in: fixture.metadata) == "Group"
        )
    }

    @Test func aTakenNameIsNumberedUntilItIsFree() throws {
        var fixture = try SceneNodeBodyFixture()
        fixture.metadata.sceneNodes[fixture.groupID]?.name = "Group"
        fixture.metadata.sceneNodes[fixture.emptyID]?.name = "Group 2"

        #expect(
            SceneNodeNameAllocator().uniqueName(base: "Group", in: fixture.metadata) == "Group 3"
        )
    }
}

/// A root holding a placed body, a lifted group containing a second body, and an empty node.
struct SceneNodeBodyFixture {
    var metadata: ProductMetadata
    let rootID: SceneNodeID
    let leftID: SceneNodeID
    let groupID: SceneNodeID
    let rightID: SceneNodeID
    let emptyID: SceneNodeID
    let bodySnapshots: [FeatureID: BodyDisplaySnapshot]

    init() throws {
        let leftFeatureID = FeatureID()
        let rightFeatureID = FeatureID()

        let left = SceneNode(
            name: "Left",
            reference: .body(leftFeatureID),
            localTransform: try .translation(Vector3D(x: 4.0, y: 0.0, z: 0.0))
        )
        let right = SceneNode(
            name: "Right",
            reference: .body(rightFeatureID),
            localTransform: try .translation(Vector3D(x: 5.0, y: 0.0, z: 0.0))
        )
        let group = SceneNode(
            name: "Lifted",
            childIDs: [right.id],
            localTransform: try .translation(Vector3D(x: 0.0, y: 1.0, z: 0.0))
        )
        let empty = SceneNode(name: "Empty")
        let root = SceneNode(name: "Scene", childIDs: [left.id, group.id, empty.id])

        metadata = ProductMetadata(
            sceneNodes: [
                root.id: root,
                left.id: left,
                group.id: group,
                right.id: right,
                empty.id: empty
            ],
            rootSceneNodeIDs: [root.id]
        )
        rootID = root.id
        leftID = left.id
        groupID = group.id
        rightID = right.id
        emptyID = empty.id
        bodySnapshots = [
            leftFeatureID: Self.unitCubeSnapshot(featureID: leftFeatureID),
            rightFeatureID: Self.unitCubeSnapshot(featureID: rightFeatureID)
        ]
    }

    private static func unitCubeSnapshot(featureID: FeatureID) -> BodyDisplaySnapshot {
        BodyDisplaySnapshot(
            featureID: featureID,
            bounds: BodyDisplaySnapshot.Bounds(
                minX: 0.0,
                minY: 0.0,
                minZ: 0.0,
                maxX: 1.0,
                maxY: 1.0,
                maxZ: 1.0
            ),
            mesh: BodyDisplaySnapshot.Mesh(positions: [], indices: []),
            topology: BodyDisplaySnapshot.Topology()
        )
    }
}
