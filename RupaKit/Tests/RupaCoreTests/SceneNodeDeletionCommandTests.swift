import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

/// Covers deleting objects from the document.
///
/// A delete is judged by two things: that it removed everything that could not outlive the selection,
/// and that a refused delete removed nothing at all. Both are checked against the document rather than
/// against the plan, because the plan is only a claim about what the document will do.
@MainActor
@Suite struct SceneNodeDeletionCommandTests {
    private struct Fixture {
        let session: EditorSession
        let rootID: SceneNodeID
        let bodyID: SceneNodeID
        let sketchID: SceneNodeID
        let bodyFeatureID: FeatureID
        let sketchFeatureID: FeatureID
    }

    /// A box, which is an extrude standing on the sketch it consumed.
    private func fixture() throws -> Fixture {
        let session = EditorSession()
        _ = try #require(session.createDefaultExtrudedRectangle())
        let metadata = session.document.productMetadata
        let bodyNode = try #require(metadata.sceneNodes.values.first { $0.reference?.kind == .body })
        let sketchNode = try #require(
            metadata.sceneNodes.values.first { $0.reference?.kind == .sketch }
        )
        return Fixture(
            session: session,
            rootID: try #require(metadata.rootSceneNodeIDs.first),
            bodyID: bodyNode.id,
            sketchID: sketchNode.id,
            bodyFeatureID: try #require(bodyNode.reference?.featureID),
            sketchFeatureID: try #require(sketchNode.reference?.featureID)
        )
    }

    @Test func deletingABodyTakesTheSketchItConsumed() throws {
        let fixture = try fixture()

        _ = try fixture.session.execute(.deleteSceneNodes(ids: [fixture.bodyID]))

        let metadata = fixture.session.document.productMetadata
        let graph = fixture.session.document.cadDocument.designGraph
        #expect(metadata.sceneNodes[fixture.bodyID] == nil)
        #expect(metadata.sceneNodes[fixture.sketchID] == nil)
        #expect(graph.nodes[fixture.bodyFeatureID] == nil)
        #expect(graph.nodes[fixture.sketchFeatureID] == nil)
        #expect(metadata.sceneNodes[fixture.rootID]?.childIDs.contains(fixture.bodyID) == false)
    }

    /// Deleting a source takes what was built from it, which is the whole reason a plan is returned.
    @Test func deletingASketchTakesWhatWasBuiltFromIt() throws {
        let fixture = try fixture()

        let plan = try SceneNodeDeletionPlanner().plan(
            metadata: fixture.session.document.productMetadata,
            designGraph: fixture.session.document.cadDocument.designGraph,
            ids: [fixture.sketchID]
        )
        _ = try fixture.session.execute(.deleteSceneNodes(ids: [fixture.sketchID]))

        #expect(plan.dependentSceneNodeIDs == [fixture.bodyID])
        #expect(plan.featureIDs == [fixture.bodyFeatureID, fixture.sketchFeatureID])
        let metadata = fixture.session.document.productMetadata
        #expect(metadata.sceneNodes[fixture.sketchID] == nil)
        #expect(metadata.sceneNodes[fixture.bodyID] == nil)
        #expect(fixture.session.document.cadDocument.designGraph.nodes[fixture.bodyFeatureID] == nil)
    }

    @Test func theSceneRootCannotBeDeleted() throws {
        let fixture = try fixture()
        let nodeCountBefore = fixture.session.document.productMetadata.sceneNodes.count

        #expect(throws: EditorError.self) {
            try fixture.session.execute(.deleteSceneNodes(ids: [fixture.rootID]))
        }
        #expect(fixture.session.document.productMetadata.sceneNodes.count == nodeCountBefore)
    }

    @Test func aLockedObjectIsNotDeleted() throws {
        let fixture = try fixture()
        _ = try fixture.session.execute(
            .setSceneNodeLock(id: fixture.bodyID, isLocked: true)
        )
        let nodeCountBefore = fixture.session.document.productMetadata.sceneNodes.count

        #expect(throws: EditorError.self) {
            try fixture.session.execute(.deleteSceneNodes(ids: [fixture.bodyID]))
        }
        let document = fixture.session.document
        #expect(document.productMetadata.sceneNodes.count == nodeCountBefore)
        #expect(document.cadDocument.designGraph.nodes[fixture.bodyFeatureID] != nil)
    }

    /// A refusal reaches back through the selection: the sketch alone is deletable, but what stands on
    /// it is locked, and half a delete is worse than none.
    @Test func aDeleteRefusedByADependentLeavesTheDocumentUntouched() throws {
        let fixture = try fixture()
        _ = try fixture.session.execute(
            .setSceneNodeLock(id: fixture.bodyID, isLocked: true)
        )
        let nodeCountBefore = fixture.session.document.productMetadata.sceneNodes.count

        #expect(throws: EditorError.self) {
            try fixture.session.execute(.deleteSceneNodes(ids: [fixture.sketchID]))
        }
        let document = fixture.session.document
        #expect(document.productMetadata.sceneNodes.count == nodeCountBefore)
        #expect(document.productMetadata.sceneNodes[fixture.sketchID] != nil)
        #expect(document.cadDocument.designGraph.nodes[fixture.sketchFeatureID] != nil)
    }

    @Test func deletingIsASingleUndoStep() throws {
        let fixture = try fixture()
        let nodeCountBefore = fixture.session.document.productMetadata.sceneNodes.count

        _ = try fixture.session.execute(.deleteSceneNodes(ids: [fixture.bodyID]))
        _ = try fixture.session.undo()

        let document = fixture.session.document
        #expect(document.productMetadata.sceneNodes.count == nodeCountBefore)
        #expect(document.productMetadata.sceneNodes[fixture.bodyID] != nil)
        #expect(document.cadDocument.designGraph.nodes[fixture.bodyFeatureID] != nil)
    }

    @Test func deletingNothingIsRefusedRatherThanIgnored() throws {
        let fixture = try fixture()

        #expect(throws: EditorError.self) {
            try fixture.session.execute(.deleteSceneNodes(ids: []))
        }
    }

    /// The selection drives the menu and the key, and what it names is what the command receives.
    @Test func deletingTheSelectionClearsTheRowsItRemoved() throws {
        let fixture = try fixture()
        #expect(fixture.session.selectSceneNodes([fixture.bodyID]))
        #expect(fixture.session.selection.wholeSceneNodeIDs == [fixture.bodyID])

        _ = try fixture.session.execute(
            .deleteSceneNodes(ids: fixture.session.selection.wholeSceneNodeIDs)
        )

        #expect(fixture.session.document.productMetadata.sceneNodes[fixture.bodyID] == nil)
        #expect(fixture.session.selection.selectedSceneNodeIDs.isEmpty)
        #expect(fixture.session.selection.wholeSceneNodeIDs.isEmpty)
    }

    /// A face carries the scene node it was picked on, so reading scene node IDs alone would answer a
    /// picked face with the body under it and delete a whole body the user never selected.
    @Test func aPickedFaceIsNotAnObjectToDelete() throws {
        let fixture = try fixture()
        #expect(
            fixture.session.selectTarget(
                SelectionTarget(sceneNodeID: fixture.bodyID, component: .face(.bodyFaceTop))
            )
        )

        #expect(fixture.session.selection.selectedSceneNodeIDs == [fixture.bodyID])
        #expect(fixture.session.selection.wholeSceneNodeIDs.isEmpty)
        #expect(fixture.session.document.productMetadata.sceneNodes[fixture.bodyID] != nil)
    }

    /// A mixed selection still names one object once, rather than being refused or counted twice.
    @Test func aSelectionHoldingAnObjectAndItsFaceDeletesTheObject() throws {
        let fixture = try fixture()
        #expect(
            fixture.session.selectTargets([
                SelectionTarget(sceneNodeID: fixture.bodyID, component: .face(.bodyFaceTop)),
                SelectionTarget(sceneNodeID: fixture.bodyID),
            ])
        )

        #expect(fixture.session.selection.wholeSceneNodeIDs == [fixture.bodyID])
        _ = try fixture.session.execute(
            .deleteSceneNodes(ids: fixture.session.selection.wholeSceneNodeIDs)
        )
        #expect(fixture.session.document.productMetadata.sceneNodes[fixture.bodyID] == nil)
    }
}

/// Covers the rule that a pattern array owns everything it generated, deletion included.
@MainActor
@Suite struct SceneNodeDeletionPatternArrayTests {
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

    @Test func aPatternArrayOutputCannotBeDeletedDirectly() throws {
        let patterned = try patternedSession()
        let outputID = try #require(
            patterned.session.document.productMetadata
                .sceneNodes[patterned.source.rootSceneNodeID]?.childIDs.first
        )
        let nodeCountBefore = patterned.session.document.productMetadata.sceneNodes.count

        #expect(throws: EditorError.self) {
            try patterned.session.execute(.deleteSceneNodes(ids: [outputID]))
        }
        #expect(
            patterned.session.document.productMetadata.sceneNodes.count == nodeCountBefore
        )
    }
}
