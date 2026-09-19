import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

private struct SceneMoveFixture {
    var document: DesignDocument
    let rootID: SceneNodeID
    let parentID: SceneNodeID
    let nestedID: SceneNodeID
    let siblingID: SceneNodeID
    let destinationID: SceneNodeID
    let trailingID: SceneNodeID
}

private func expectSameSceneMoveDocument(_ actual: DesignDocument, _ expected: DesignDocument) throws {
    #expect(actual.productMetadata == expected.productMetadata)
    #expect(actual.modelingSettings == expected.modelingSettings)
    #expect(actual.authoredMeshAssets == expected.authoredMeshAssets)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    #expect(try encoder.encode(actual.cadDocument) == encoder.encode(expected.cadDocument))
}

private func sceneMoveTransform(_ translationX: Double) throws -> Transform3D {
    Transform3D(
        matrix: try Matrix4x4(values: [
            1.0, 0.0, 0.0, translationX,
            0.0, 1.0, 0.0, 0.0,
            0.0, 0.0, 1.0, 0.0,
            0.0, 0.0, 0.0, 1.0,
        ])
    )
}

private func makeSceneMoveFixture() throws -> SceneMoveFixture {
    var document = DesignDocument.empty(named: "Scene move fixture")
    guard let rootID = document.productMetadata.rootSceneNodeIDs.first else {
        throw EditorError(code: .commandFailed, message: "Scene move fixture has no root.")
    }

    let nested = SceneNode(
        name: "Nested",
        localTransform: try sceneMoveTransform(2.0)
    )
    let parent = SceneNode(
        name: "Parent",
        childIDs: [nested.id],
        localTransform: try sceneMoveTransform(10.0)
    )
    let sibling = SceneNode(name: "Sibling")
    let destination = SceneNode(
        name: "Destination",
        localTransform: try sceneMoveTransform(-5.0)
    )
    let trailing = SceneNode(name: "Trailing")
    document.productMetadata.sceneNodes[nested.id] = nested
    document.productMetadata.sceneNodes[parent.id] = parent
    document.productMetadata.sceneNodes[sibling.id] = sibling
    document.productMetadata.sceneNodes[destination.id] = destination
    document.productMetadata.sceneNodes[trailing.id] = trailing
    guard var root = document.productMetadata.sceneNodes[rootID] else {
        throw EditorError(code: .commandFailed, message: "Scene move fixture root disappeared.")
    }
    root.childIDs = [parent.id, sibling.id, destination.id, trailing.id]
    document.productMetadata.sceneNodes[rootID] = root
    try document.productMetadata.validate(
        against: document.cadDocument,
        objectRegistry: .builtIn
    )
    return SceneMoveFixture(
        document: document,
        rootID: rootID,
        parentID: parent.id,
        nestedID: nested.id,
        siblingID: sibling.id,
        destinationID: destination.id,
        trailingID: trailing.id
    )
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func moveSceneNodesReordersCurrentSceneOrderAndPreservesLocalTransformBits() throws {
    let fixture = try makeSceneMoveFixture()
    let session = EditorSession(document: fixture.document)
    let beforeParentTransform = try #require(
        session.document.productMetadata.sceneNodes[fixture.parentID]?.localTransform.matrix.values
    )
    let beforeTrailingTransform = try #require(
        session.document.productMetadata.sceneNodes[fixture.trailingID]?.localTransform.matrix.values
    )

    let result = try session.execute(.moveSceneNodes(
        ids: [fixture.trailingID, fixture.parentID],
        parentID: fixture.rootID,
        beforeSiblingID: fixture.destinationID
    ))

    #expect(result.commandName == "moveSceneNodes")
    #expect(result.didMutate)
    #expect(session.document.productMetadata.sceneNodes[fixture.rootID]?.childIDs == [
        fixture.siblingID,
        fixture.parentID,
        fixture.trailingID,
        fixture.destinationID,
    ])
    #expect(session.document.productMetadata.sceneNodes[fixture.parentID]?.childIDs == [fixture.nestedID])
    #expect(
        session.document.productMetadata.sceneNodes[fixture.parentID]?.localTransform.matrix.values
            == beforeParentTransform
    )
    #expect(
        session.document.productMetadata.sceneNodes[fixture.trailingID]?.localTransform.matrix.values
            == beforeTrailingTransform
    )
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.commandStack.undoEntries.count == 1)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func moveSceneNodesCollapsesDescendantSelectionAndPreservesWorldPlacement() throws {
    let fixture = try makeSceneMoveFixture()
    let session = EditorSession(document: fixture.document)

    let result = try session.execute(.moveSceneNodes(
        ids: [fixture.nestedID, fixture.parentID],
        parentID: fixture.destinationID,
        beforeSiblingID: nil
    ))

    #expect(result.didMutate)
    #expect(session.document.productMetadata.sceneNodes[fixture.parentID]?.childIDs == [fixture.nestedID])
    #expect(session.document.productMetadata.sceneNodes[fixture.destinationID]?.childIDs == [fixture.parentID])
    #expect(
        session.document.productMetadata.sceneNodes[fixture.nestedID]?.localTransform.matrix.values[3]
            == 2.0
    )
    #expect(
        session.document.productMetadata.sceneNodes[fixture.parentID]?.localTransform.matrix.values[3]
            == 15.0
    )

    let movedParent = try #require(session.document.productMetadata.sceneNodes[fixture.parentID])
    let movedDestination = try #require(session.document.productMetadata.sceneNodes[fixture.destinationID])
    let worldX = movedDestination.localTransform.matrix.values[3]
        + movedParent.localTransform.matrix.values[3]
        + movedParent.childIDs.compactMap {
            session.document.productMetadata.sceneNodes[$0]?.localTransform.matrix.values[3]
        }.reduce(0.0, +)
    #expect(worldX == 12.0)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func moveSceneNodesPreservesRootListAndSupportsRootReorder() throws {
    var fixture = try makeSceneMoveFixture()
    let secondRoot = SceneNode(name: "Second root")
    fixture.document.productMetadata.sceneNodes[secondRoot.id] = secondRoot
    fixture.document.productMetadata.rootSceneNodeIDs.append(secondRoot.id)
    try fixture.document.productMetadata.validate(
        against: fixture.document.cadDocument,
        objectRegistry: .builtIn
    )
    let session = EditorSession(document: fixture.document)

    let result = try session.execute(.moveSceneNodes(
        ids: [secondRoot.id],
        parentID: nil,
        beforeSiblingID: fixture.rootID
    ))

    #expect(result.didMutate)
    #expect(session.document.productMetadata.rootSceneNodeIDs == [secondRoot.id, fixture.rootID])
    #expect(!session.document.productMetadata.rootSceneNodeIDs.isEmpty)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func moveSceneNodesSameParentNoOpDoesNotPublishGenerationOrHistory() throws {
    let fixture = try makeSceneMoveFixture()
    let session = EditorSession(document: fixture.document)
    let beforeDocument = session.document
    let beforeGeneration = session.generation
    let beforeRevision = session.transactionRevision
    let beforeEvaluationPassCount = session.store.completedEvaluationPassCount

    let result = try session.execute(.moveSceneNodes(
        ids: [fixture.parentID],
        parentID: fixture.rootID,
        beforeSiblingID: fixture.siblingID
    ))

    #expect(!result.didMutate)
    try expectSameSceneMoveDocument(session.document, beforeDocument)
    #expect(session.generation == beforeGeneration)
    #expect(session.transactionRevision == beforeRevision)
    #expect(session.store.completedEvaluationPassCount == beforeEvaluationPassCount)
    #expect(session.commandStack.undoEntries.isEmpty)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func moveSceneNodesRejectsCycleAndInvalidAnchorAtomically() throws {
    let fixture = try makeSceneMoveFixture()
    let session = EditorSession(document: fixture.document)
    let beforeDocument = session.document
    let beforeGeneration = session.generation

    do {
        _ = try session.execute(.moveSceneNodes(
            ids: [fixture.parentID],
            parentID: fixture.nestedID,
            beforeSiblingID: nil
        ))
        Issue.record("Moving a parent into its descendant must fail.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
    }
    try expectSameSceneMoveDocument(session.document, beforeDocument)
    #expect(session.generation == beforeGeneration)

    do {
        _ = try session.execute(.moveSceneNodes(
            ids: [fixture.trailingID],
            parentID: fixture.destinationID,
            beforeSiblingID: fixture.siblingID
        ))
        Issue.record("An anchor outside the destination sibling list must fail.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
    }
    try expectSameSceneMoveDocument(session.document, beforeDocument)
    #expect(session.generation == beforeGeneration)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func moveSceneNodesRejectsEmptyDuplicateMissingAndNonInvertiblePlacement() throws {
    let fixture = try makeSceneMoveFixture()
    let session = EditorSession(document: fixture.document)
    let beforeDocument = session.document

    do {
        _ = try session.execute(.moveSceneNodes(
            ids: [],
            parentID: fixture.destinationID,
            beforeSiblingID: nil
        ))
        Issue.record("An empty scene node selection must fail.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
    }
    try expectSameSceneMoveDocument(session.document, beforeDocument)

    do {
        _ = try session.execute(.moveSceneNodes(
            ids: [fixture.trailingID, fixture.trailingID],
            parentID: fixture.destinationID,
            beforeSiblingID: nil
        ))
        Issue.record("A duplicate scene node selection must fail.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
    }
    try expectSameSceneMoveDocument(session.document, beforeDocument)

    do {
        _ = try session.execute(.moveSceneNodes(
            ids: [SceneNodeID()],
            parentID: fixture.destinationID,
            beforeSiblingID: nil
        ))
        Issue.record("A missing scene node selection must fail.")
    } catch let error as EditorError {
        #expect(error.code == .referenceUnresolved)
    }
    try expectSameSceneMoveDocument(session.document, beforeDocument)

    var singularFixture = try makeSceneMoveFixture()
    singularFixture.document.productMetadata.sceneNodes[singularFixture.parentID]?.localTransform = Transform3D(
        matrix: try Matrix4x4(values: [
            0.0, 0.0, 0.0, 10.0,
            0.0, 1.0, 0.0, 0.0,
            0.0, 0.0, 1.0, 0.0,
            0.0, 0.0, 0.0, 1.0,
        ])
    )
    let singularSession = EditorSession(document: singularFixture.document)
    let singularBefore = singularSession.document
    do {
        _ = try singularSession.execute(.moveSceneNodes(
            ids: [singularFixture.parentID],
            parentID: singularFixture.destinationID,
            beforeSiblingID: nil
        ))
        Issue.record("A non-invertible source placement must fail.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
    }
    try expectSameSceneMoveDocument(singularSession.document, singularBefore)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func moveSceneNodesRejectsLockedAndComponentDefinitionSourceNodes() throws {
    var fixture = try makeSceneMoveFixture()
    fixture.document.productMetadata.sceneNodes[fixture.destinationID]?.isLocked = true
    let session = EditorSession(document: fixture.document)
    let beforeDocument = session.document

    do {
        _ = try session.execute(.moveSceneNodes(
            ids: [fixture.parentID],
            parentID: fixture.destinationID,
            beforeSiblingID: nil
        ))
        Issue.record("A locked destination must reject a move.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
    }
    try expectSameSceneMoveDocument(session.document, beforeDocument)

    let sourceFixture = try makeSceneMoveFixture()
    var sourceDocument = sourceFixture.document
    let sourceRootID = try #require(sourceDocument.productMetadata.rootSceneNodeIDs.first)
    let definitionID = try sourceDocument.createComponentDefinition(
        name: "Source",
        rootSceneNodeIDs: [sourceFixture.parentID]
    )
    #expect(sourceDocument.productMetadata.componentDefinitions[definitionID] != nil)
    let sourceSession = EditorSession(document: sourceDocument)
    let sourceBefore = sourceSession.document
    do {
        _ = try sourceSession.execute(.moveSceneNodes(
            ids: [sourceFixture.siblingID],
            parentID: sourceFixture.parentID,
            beforeSiblingID: nil
        ))
        Issue.record("A component definition source parent must reject a move.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
    }
    try expectSameSceneMoveDocument(sourceSession.document, sourceBefore)
    #expect(sourceSession.document.productMetadata.rootSceneNodeIDs.contains(sourceRootID))
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func moveSceneNodesRejectsPatternOwnedOutputSubtrees() throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(
        session.document.productMetadata.sceneNodes.values.first {
            $0.reference == .body(bodyFeatureID)
        }?.id
    )
    let definitionResult = try session.execute(
        .createComponentDefinition(
            name: "Pattern source",
            rootSceneNodeIDs: [bodySceneNodeID]
        )
    )
    let definitionID = try #require(definitionResult.generatedIdentities.componentDefinitionIDs.first)
    let patternResult = try session.execute(
        .createPatternArray(
            name: "Pattern",
            definitionID: definitionID,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: .unitX,
                    distance: .length(10, .millimeter),
                    copyCount: 2
                )
            )),
            outputMode: .componentInstance
        )
    )
    let patternID = try #require(patternResult.generatedIdentities.patternArraySourceIDs.first)
    let pattern = try #require(session.document.productMetadata.patternArrays[patternID])
    let outputID = try #require(
        session.document.productMetadata.sceneNodes[pattern.rootSceneNodeID]?.childIDs.first
    )
    let rootID = try #require(session.document.productMetadata.rootSceneNodeIDs.first)
    let beforeDocument = session.document

    do {
        _ = try session.execute(.moveSceneNodes(
            ids: [outputID],
            parentID: rootID,
            beforeSiblingID: nil
        ))
        Issue.record("Pattern output scene nodes must be source-owned.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
    }
    try expectSameSceneMoveDocument(session.document, beforeDocument)

    var reorderDocument = beforeDocument
    let ordinary = SceneNode(name: "Ordinary sibling")
    reorderDocument.productMetadata.sceneNodes[ordinary.id] = ordinary
    reorderDocument.productMetadata.sceneNodes[rootID]?.childIDs.append(ordinary.id)
    let reorderSession = EditorSession(document: reorderDocument)
    _ = try reorderSession.execute(.moveSceneNodes(
        ids: [ordinary.id], parentID: rootID, beforeSiblingID: pattern.rootSceneNodeID
    ))
    let siblings = try #require(reorderSession.document.productMetadata.sceneNodes[rootID]?.childIDs)
    let patternIndex = try #require(siblings.firstIndex(of: pattern.rootSceneNodeID))
    #expect(patternIndex > 0)
    #expect(siblings[patternIndex - 1] == ordinary.id)
    #expect(reorderSession.document.productMetadata.patternArrays == reorderDocument.productMetadata.patternArrays)
    #expect(reorderSession.document.productMetadata.sceneNodes[pattern.rootSceneNodeID]
        == reorderDocument.productMetadata.sceneNodes[pattern.rootSceneNodeID])
    #expect(reorderSession.document.productMetadata.sceneNodes[outputID]
        == reorderDocument.productMetadata.sceneNodes[outputID])
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func moveSceneNodesDetachesSelectionFromDifferentParentsToSceneRoots() throws {
    let fixture = try makeSceneMoveFixture()
    let session = EditorSession(document: fixture.document)
    _ = try session.execute(.moveSceneNodes(
        ids: [fixture.trailingID, fixture.nestedID], parentID: nil, beforeSiblingID: nil
    ))
    #expect(session.document.productMetadata.rootSceneNodeIDs
        == [fixture.rootID, fixture.nestedID, fixture.trailingID])
    #expect(session.document.productMetadata.sceneNodes[fixture.parentID]?.childIDs.isEmpty == true)
    #expect(session.document.productMetadata.sceneNodes[fixture.nestedID]?.localTransform.matrix.values[3] == 12)
    #expect(session.document.productMetadata.sceneNodes[fixture.trailingID]?.localTransform.matrix.values[3] == 0)
    #expect(session.commandStack.undoEntries.count == 1)
    _ = try session.undo()
    try expectSameSceneMoveDocument(session.document, fixture.document)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func moveSceneNodesRejectsStaleGenerationAndSupportsOneStepUndoRedo() throws {
    let fixture = try makeSceneMoveFixture()
    let session = EditorSession(document: fixture.document)
    let command = EditorCommand.moveSceneNodes(
        ids: [fixture.trailingID],
        parentID: fixture.destinationID,
        beforeSiblingID: nil
    )
    let beforeDocument = session.document

    do {
        _ = try session.execute(command, expectedGeneration: DocumentGeneration(1))
        Issue.record("A stale generation must reject the move.")
    } catch let error as EditorError {
        #expect(error.code == .documentGenerationMismatch)
    }
    try expectSameSceneMoveDocument(session.document, beforeDocument)
    #expect(session.generation == DocumentGeneration(0))

    _ = try session.execute(command, expectedGeneration: DocumentGeneration(0))
    #expect(session.commandStack.undoEntries.count == 1)
    #expect(session.document.productMetadata.sceneNodes[fixture.destinationID]?.childIDs == [fixture.trailingID])

    _ = try session.undo()
    #expect(session.document.productMetadata.sceneNodes[fixture.destinationID]?.childIDs.isEmpty == true)
    _ = try session.redo()
    #expect(session.document.productMetadata.sceneNodes[fixture.destinationID]?.childIDs == [fixture.trailingID])
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func moveSceneNodesUsesRowMajorAffineInverseForRotatedNonUniformParents() throws {
    var fixture = try makeSceneMoveFixture()
    let sourceParentTransform = Transform3D(
        matrix: try Matrix4x4(values: [
            0.0, 2.0, 0.0, 7.0,
            -3.0, 0.0, 0.0, -2.0,
            0.0, 0.0, 5.0, 3.0,
            0.0, 0.0, 0.0, 1.0,
        ])
    )
    let destinationTransform = Transform3D(
        matrix: try Matrix4x4(values: [
            0.0, -3.0, 0.0, -4.0,
            2.0, 0.0, 0.0, 5.0,
            0.0, 0.0, 4.0, 1.0,
            0.0, 0.0, 0.0, 1.0,
        ])
    )
    let nestedTransform = Transform3D(
        matrix: try Matrix4x4(values: [
            0.0, -1.0, 0.0, 1.0,
            1.0, 0.0, 0.0, 2.0,
            0.0, 0.0, 1.0, 3.0,
            0.0, 0.0, 0.0, 1.0,
        ])
    )
    fixture.document.productMetadata.sceneNodes[fixture.parentID]?.localTransform = sourceParentTransform
    fixture.document.productMetadata.sceneNodes[fixture.destinationID]?.localTransform = destinationTransform
    fixture.document.productMetadata.sceneNodes[fixture.nestedID]?.localTransform = nestedTransform
    try fixture.document.productMetadata.validate(
        against: fixture.document.cadDocument,
        objectRegistry: .builtIn
    )
    let session = EditorSession(document: fixture.document)

    _ = try session.execute(.moveSceneNodes(
        ids: [fixture.nestedID],
        parentID: fixture.destinationID,
        beforeSiblingID: nil
    ))

    let moved = try #require(
        session.document.productMetadata.sceneNodes[fixture.nestedID]?.localTransform.matrix.values
    )
    let expected = [
        0.0, 1.5, 0.0, -5.0,
        -2.0 / 3.0, 0.0, 0.0, -5.0,
        0.0, 0.0, 1.25, 4.25,
        0.0, 0.0, 0.0, 1.0,
    ]
    #expect(moved.count == expected.count)
    for (actual, expectedValue) in zip(moved, expected) {
        #expect(abs(actual - expectedValue) < 1e-12)
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func moveSceneNodesPreservesComponentInstanceAuthorityTransformWhenMovingOccurrence() throws {
    var fixture = try makeSceneMoveFixture()
    let definitionID = try fixture.document.createComponentDefinition(
        name: "Movable component",
        rootSceneNodeIDs: [fixture.parentID]
    )
    let authorityTransform = Transform3D(
        matrix: try Matrix4x4(values: [
            1.0, 0.0, 0.0, 4.0,
            0.0, 1.0, 0.0, 3.0,
            0.0, 0.0, 1.0, 2.0,
            0.0, 0.0, 0.0, 1.0,
        ])
    )
    let instanceID = try fixture.document.createComponentInstance(
        name: "Movable occurrence",
        definitionID: definitionID,
        localTransform: authorityTransform
    )
    let occurrenceID = try #require(
        fixture.document.productMetadata.sceneNodes.values.first {
            $0.reference == .componentInstance(instanceID)
        }?.id
    )
    let beforeAuthority = try #require(
        fixture.document.productMetadata.componentInstances[instanceID]?.localTransform
    )
    let beforeOccurrence = try #require(
        fixture.document.productMetadata.sceneNodes[occurrenceID]?.localTransform
    )
    try fixture.document.productMetadata.validate(
        against: fixture.document.cadDocument,
        objectRegistry: .builtIn
    )
    let session = EditorSession(document: fixture.document)

    _ = try session.execute(.moveSceneNodes(
        ids: [occurrenceID],
        parentID: fixture.destinationID,
        beforeSiblingID: nil
    ))

    #expect(
        session.document.productMetadata.componentInstances[instanceID]?.localTransform
            == beforeAuthority
    )
    #expect(
        session.document.productMetadata.sceneNodes[occurrenceID]?.localTransform
            != beforeOccurrence
    )
    #expect(
        session.document.productMetadata.sceneNodes[fixture.destinationID]?.childIDs
            .contains(occurrenceID) == true
    )
    #expect(
        session.document.productMetadata.sceneNodes[fixture.rootID]?.childIDs
            .contains(occurrenceID) == false
    )
}
