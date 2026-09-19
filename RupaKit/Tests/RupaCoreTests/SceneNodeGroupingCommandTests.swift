import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

/// Covers grouping and multi-object placement as the document performs them.
///
/// Both commands promise the same thing in different directions: restructuring the tree must leave
/// the scene looking untouched, and moving a selection must move it as one rigid body. Every test
/// checks world placements before and after, because that is the only thing the user can see.
@MainActor
@Suite struct SceneNodeGroupingCommandTests {
    private let tolerance = 1.0e-9

    private struct Fixture {
        let session: EditorSession
        let rootID: SceneNodeID
        let firstID: SceneNodeID
        let secondID: SceneNodeID
    }

    private func fixture() throws -> Fixture {
        let session = EditorSession()
        _ = try #require(session.createDefaultExtrudedRectangle())
        let firstFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
        _ = try #require(session.createDefaultExtrudedRectangle())
        let secondFeatureID = try #require(session.document.cadDocument.designGraph.order.last)

        let firstID = try #require(sceneNodeID(for: firstFeatureID, in: session))
        let secondID = try #require(sceneNodeID(for: secondFeatureID, in: session))
        let rootID = try #require(session.document.productMetadata.rootSceneNodeIDs.first)

        _ = try session.execute(
            .setSceneNodeTransform(
                id: firstID,
                localTransform: try .translation(Vector3D(x: 1.0, y: 0.0, z: 0.0))
            )
        )
        _ = try session.execute(
            .setSceneNodeTransform(
                id: secondID,
                localTransform: try .translation(Vector3D(x: 0.0, y: 2.0, z: 0.0))
            )
        )
        return Fixture(session: session, rootID: rootID, firstID: firstID, secondID: secondID)
    }

    private func sceneNodeID(for featureID: FeatureID, in session: EditorSession) -> SceneNodeID? {
        session.document.productMetadata.sceneNodes.values.first {
            $0.reference?.featureID == featureID && $0.reference?.kind == .body
        }?.id
    }

    private func worldOrigin(
        of id: SceneNodeID,
        in session: EditorSession
    ) throws -> Point3D {
        try SceneNodeHierarchy(metadata: session.document.productMetadata)
            .worldTransform(of: id)
            .applied(to: .origin)
    }

    private func groupNodeID(named name: String, in session: EditorSession) -> SceneNodeID? {
        session.document.productMetadata.sceneNodes.values.first {
            $0.name == name && $0.isGroupingNode
        }?.id
    }

    @Test func groupingHoldsEveryMemberWhereItWas() throws {
        let fixture = try fixture()
        let firstBefore = try worldOrigin(of: fixture.firstID, in: fixture.session)
        let secondBefore = try worldOrigin(of: fixture.secondID, in: fixture.session)

        let result = try fixture.session.groupSceneNodes(
            name: "Assembly",
            memberIDs: [fixture.firstID, fixture.secondID]
        )
        let groupID = try #require(result.createdSceneNodeID)
        let group = try #require(fixture.session.document.productMetadata.sceneNodes[groupID])

        #expect(group.childIDs == [fixture.firstID, fixture.secondID])
        #expect(
            fixture.session.document.productMetadata.sceneNodes[fixture.rootID]?.childIDs
                .contains(groupID) == true
        )
        #expect(
            fixture.session.document.productMetadata.sceneNodes[fixture.rootID]?.childIDs
                .contains(fixture.firstID) == false
        )
        #expect(try worldOrigin(of: fixture.firstID, in: fixture.session)
            .isApproximatelyEqual(to: firstBefore, tolerance: tolerance))
        #expect(try worldOrigin(of: fixture.secondID, in: fixture.session)
            .isApproximatelyEqual(to: secondBefore, tolerance: tolerance))
    }

    @Test func groupingAtAnOriginPlacesTheGroupThereWithoutMovingItsMembers() throws {
        let fixture = try fixture()
        let firstBefore = try worldOrigin(of: fixture.firstID, in: fixture.session)
        let origin = Point3D(x: 0.5, y: 1.0, z: 0.0)

        let result = try fixture.session.groupSceneNodes(
            name: "Assembly",
            memberIDs: [fixture.firstID, fixture.secondID],
            origin: origin
        )
        let groupID = try #require(result.createdSceneNodeID)

        #expect(try worldOrigin(of: groupID, in: fixture.session)
            .isApproximatelyEqual(to: origin, tolerance: tolerance))
        #expect(try worldOrigin(of: fixture.firstID, in: fixture.session)
            .isApproximatelyEqual(to: firstBefore, tolerance: tolerance))
    }

    @Test func ungroupingHoldsEveryMemberWhereItWas() throws {
        let fixture = try fixture()
        let firstBefore = try worldOrigin(of: fixture.firstID, in: fixture.session)
        let secondBefore = try worldOrigin(of: fixture.secondID, in: fixture.session)
        let grouping = try fixture.session.groupSceneNodes(
            name: "Assembly",
            memberIDs: [fixture.firstID, fixture.secondID],
            origin: Point3D(x: 0.5, y: 1.0, z: 0.0)
        )
        let groupID = try #require(grouping.createdSceneNodeID)

        _ = try fixture.session.ungroupSceneNode(groupID)

        #expect(fixture.session.document.productMetadata.sceneNodes[groupID] == nil)
        #expect(
            fixture.session.document.productMetadata.sceneNodes[fixture.rootID]?.childIDs
                .filter { $0 == fixture.firstID || $0 == fixture.secondID }
                == [fixture.firstID, fixture.secondID]
        )
        #expect(try worldOrigin(of: fixture.firstID, in: fixture.session)
            .isApproximatelyEqual(to: firstBefore, tolerance: tolerance))
        #expect(try worldOrigin(of: fixture.secondID, in: fixture.session)
            .isApproximatelyEqual(to: secondBefore, tolerance: tolerance))
    }

    @Test func ungroupingAHiddenGroupKeepsItsMembersOutOfSight() throws {
        let fixture = try fixture()
        let grouping = try fixture.session.groupSceneNodes(
            name: "Assembly",
            memberIDs: [fixture.firstID, fixture.secondID]
        )
        let groupID = try #require(grouping.createdSceneNodeID)
        fixture.session.setSceneNodeVisibility(groupID, isVisible: false)

        _ = try fixture.session.ungroupSceneNode(groupID)

        #expect(
            fixture.session.document.productMetadata.sceneNodes[fixture.firstID]?.isVisible == false
        )
        #expect(
            fixture.session.document.productMetadata.sceneNodes[fixture.secondID]?.isVisible == false
        )
    }

    @Test func aNodeThatCarriesGeometryCannotBeUngrouped() throws {
        let fixture = try fixture()

        #expect(throws: EditorError.self) {
            try fixture.session.execute(.ungroupSceneNode(id: fixture.firstID))
        }
    }

    @Test func theSceneRootCannotBeGrouped() throws {
        let fixture = try fixture()

        #expect(throws: EditorError.self) {
            try fixture.session.execute(
                .groupSceneNodes(name: "Assembly", memberIDs: [fixture.rootID], origin: nil)
            )
        }
    }

    @Test func movingASelectionMovesEveryMemberByTheSameDelta() throws {
        let fixture = try fixture()
        let firstBefore = try worldOrigin(of: fixture.firstID, in: fixture.session)
        let secondBefore = try worldOrigin(of: fixture.secondID, in: fixture.session)
        let delta = Vector3D(x: 3.0, y: -1.0, z: 0.5)

        _ = try fixture.session.moveSceneNodes([fixture.firstID, fixture.secondID], by: delta)

        #expect(try worldOrigin(of: fixture.firstID, in: fixture.session)
            .isApproximatelyEqual(to: firstBefore + delta, tolerance: tolerance))
        #expect(try worldOrigin(of: fixture.secondID, in: fixture.session)
            .isApproximatelyEqual(to: secondBefore + delta, tolerance: tolerance))
    }

    @Test func rotatingASelectionHoldsItsArrangement() throws {
        let fixture = try fixture()
        let firstBefore = try worldOrigin(of: fixture.firstID, in: fixture.session)
        let secondBefore = try worldOrigin(of: fixture.secondID, in: fixture.session)

        _ = try fixture.session.rotateSceneNodes(
            [fixture.firstID, fixture.secondID],
            axis: .unitZ,
            angleRadians: .pi / 2.0,
            about: .origin
        )

        let firstAfter = try worldOrigin(of: fixture.firstID, in: fixture.session)
        let secondAfter = try worldOrigin(of: fixture.secondID, in: fixture.session)

        // A quarter turn about Z sends (x, y) to (-y, x), and the members stay the same distance
        // apart because they turned about one shared point rather than each about itself.
        #expect(firstAfter.isApproximatelyEqual(
            to: Point3D(x: -firstBefore.y, y: firstBefore.x, z: firstBefore.z),
            tolerance: tolerance
        ))
        #expect(secondAfter.isApproximatelyEqual(
            to: Point3D(x: -secondBefore.y, y: secondBefore.x, z: secondBefore.z),
            tolerance: tolerance
        ))
        #expect(abs((secondAfter - firstAfter).length - (secondBefore - firstBefore).length) < tolerance)
    }

    @Test func aMemberSelectedAlongsideItsGroupIsMovedOnlyOnce() throws {
        let fixture = try fixture()
        let grouping = try fixture.session.groupSceneNodes(
            name: "Assembly",
            memberIDs: [fixture.firstID, fixture.secondID]
        )
        let groupID = try #require(grouping.createdSceneNodeID)
        let firstBefore = try worldOrigin(of: fixture.firstID, in: fixture.session)
        let delta = Vector3D(x: 2.0, y: 0.0, z: 0.0)

        _ = try fixture.session.moveSceneNodes([groupID, fixture.firstID], by: delta)

        #expect(try worldOrigin(of: fixture.firstID, in: fixture.session)
            .isApproximatelyEqual(to: firstBefore + delta, tolerance: tolerance))
    }

    @Test func aMemberOfATurnedGroupStillMovesAlongWorldAxes() throws {
        let fixture = try fixture()
        let grouping = try fixture.session.groupSceneNodes(
            name: "Assembly",
            memberIDs: [fixture.firstID, fixture.secondID]
        )
        let groupID = try #require(grouping.createdSceneNodeID)
        _ = try fixture.session.rotateSceneNodes(
            [groupID],
            axis: .unitZ,
            angleRadians: .pi / 2.0,
            about: .origin
        )
        let firstBefore = try worldOrigin(of: fixture.firstID, in: fixture.session)
        let delta = Vector3D(x: 1.0, y: 0.0, z: 0.0)

        _ = try fixture.session.moveSceneNodes([fixture.firstID], by: delta)

        #expect(try worldOrigin(of: fixture.firstID, in: fixture.session)
            .isApproximatelyEqual(to: firstBefore + delta, tolerance: tolerance))
    }

    @Test func groupingIsASingleUndoStep() throws {
        let fixture = try fixture()
        let rootChildrenBefore = try #require(
            fixture.session.document.productMetadata.sceneNodes[fixture.rootID]?.childIDs
        )
        let grouping = try fixture.session.groupSceneNodes(
            name: "Assembly",
            memberIDs: [fixture.firstID, fixture.secondID]
        )
        let groupID = try #require(grouping.createdSceneNodeID)

        _ = try fixture.session.undo()

        #expect(fixture.session.document.productMetadata.sceneNodes[groupID] == nil)
        #expect(
            fixture.session.document.productMetadata.sceneNodes[fixture.rootID]?.childIDs
                == rootChildrenBefore
        )
    }
}

/// Covers the rule that a pattern array owns the placement of everything it generated.
@MainActor
@Suite struct SceneNodePatternArrayOwnershipTests {
    private func patternedSession() throws -> (session: EditorSession, source: PatternArraySource) {
        let session = EditorSession()
        _ = try #require(session.createDefaultExtrudedRectangle())
        let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
        let bodySceneNodeID = try #require(
            session.document.productMetadata.sceneNodes.values.first {
                $0.reference?.featureID == bodyFeatureID
            }?.id
        )
        _ = try session.execute(
            .createComponentDefinition(
                name: "Patterned Source",
                rootSceneNodeIDs: [bodySceneNodeID]
            )
        )
        let definition = try #require(
            session.document.productMetadata.componentDefinitions.values.first {
                $0.name == "Patterned Source"
            }
        )
        _ = try session.execute(
            .createPatternArray(
                name: "Patterned Array",
                definitionID: definition.id,
                distribution: .rectangular(RectangularPatternArray(
                    firstAxis: PatternArrayLinearAxis(
                        direction: .unitX,
                        distance: .length(10.0, .millimeter),
                        copyCount: 1
                    )
                )),
                outputMode: .independentCopy
            )
        )
        let source = try #require(
            session.document.productMetadata.patternArrays.values.first {
                $0.name == "Patterned Array"
            }
        )
        return (session: session, source: source)
    }

    @Test func aPatternArrayOutputCannotBeTransformedDirectly() throws {
        let patterned = try patternedSession()
        let outputID = try #require(
            patterned.session.document.productMetadata
                .sceneNodes[patterned.source.rootSceneNodeID]?.childIDs.first
        )

        #expect(throws: EditorError.self) {
            try patterned.session.execute(
                .transformSceneNodes(
                    ids: [outputID],
                    worldDelta: try .translation(Vector3D(x: 1.0, y: 0.0, z: 0.0))
                )
            )
        }
    }

    @Test func aPatternArrayOutputCannotBeGrouped() throws {
        let patterned = try patternedSession()
        let outputID = try #require(
            patterned.session.document.productMetadata
                .sceneNodes[patterned.source.rootSceneNodeID]?.childIDs.first
        )

        #expect(throws: EditorError.self) {
            try patterned.session.execute(
                .groupSceneNodes(name: "Assembly", memberIDs: [outputID], origin: nil)
            )
        }
    }
}

/// Drives the lifecycle commands the way the workspace submits them.
///
/// The tests above read as the actions a user takes; translating an action into its command belongs
/// in one place so that every test exercises the path the UI actually submits rather than a
/// convenience the workspace does not use.
@MainActor
private extension EditorSession {
    func groupSceneNodes(
        name: String,
        memberIDs: [SceneNodeID],
        origin: Point3D? = nil
    ) throws -> CommandExecutionResult {
        try execute(.groupSceneNodes(name: name, memberIDs: memberIDs, origin: origin))
    }

    @discardableResult
    func ungroupSceneNode(_ id: SceneNodeID) throws -> CommandExecutionResult {
        try execute(.ungroupSceneNode(id: id))
    }

    @discardableResult
    func moveSceneNodes(
        _ ids: [SceneNodeID],
        by translation: Vector3D
    ) throws -> CommandExecutionResult {
        try execute(
            .transformSceneNodes(ids: ids, worldDelta: try .translation(translation))
        )
    }

    func rotateSceneNodes(
        _ ids: [SceneNodeID],
        axis: Vector3D,
        angleRadians: Double,
        about pivot: Point3D
    ) throws -> CommandExecutionResult {
        try execute(
            .transformSceneNodes(
                ids: ids,
                worldDelta: try .rotation(axis: axis, angleRadians: angleRadians, about: pivot)
            )
        )
    }
}

private extension CommandExecutionResult {
    /// The scene node a grouping command created.
    var createdSceneNodeID: SceneNodeID? {
        generatedIdentities.sceneNodeIDs.first
    }
}
