import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

@MainActor
@Test(.timeLimit(.minutes(1)))
func renameSceneNodeNormalizesNameAndPreservesNodeState() throws {
    let session = EditorSession()
    let nodeID = try #require(session.document.productMetadata.rootSceneNodeIDs.first)
    let before = try #require(session.document.productMetadata.sceneNodes[nodeID])

    let result = try session.execute(
        .renameSceneNode(id: nodeID, name: "  Renamed Scene  ")
    )

    let after = try #require(session.document.productMetadata.sceneNodes[nodeID])
    var expected = before
    expected.name = "Renamed Scene"
    #expect(result.commandName == "renameSceneNode")
    #expect(result.didMutate)
    #expect(after == expected)
    #expect(session.document.cadDocument.metadata.name == "Untitled")
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func renameSceneNodeWithTheExistingNormalizedNameIsNoOp() throws {
    let session = EditorSession()
    let nodeID = try #require(session.document.productMetadata.rootSceneNodeIDs.first)
    let beforeNode = try #require(session.document.productMetadata.sceneNodes[nodeID])
    let beforeMetadata = session.document.productMetadata
    let beforeGeneration = session.generation
    let beforeTransactionRevision = session.transactionRevision
    let beforeEvaluationPassCount = session.store.completedEvaluationPassCount

    let result = try session.execute(
        .renameSceneNode(id: nodeID, name: "  \(beforeNode.name)  ")
    )

    #expect(!result.didMutate)
    #expect(result.generation == beforeGeneration)
    #expect(session.generation == beforeGeneration)
    #expect(session.transactionRevision == beforeTransactionRevision)
    #expect(session.store.completedEvaluationPassCount == beforeEvaluationPassCount)
    #expect(!session.isDirty)
    #expect(session.commandStack.undoEntries.isEmpty)
    #expect(session.document.productMetadata == beforeMetadata)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func renameComponentInstanceUpdatesAuthorityAndAllOccurrences() throws {
    var document = DesignDocument.empty()
    let rootSceneNodeID = try #require(document.productMetadata.rootSceneNodeIDs.first)
    let definitionID = try document.createComponentDefinition(
        name: "Frame",
        rootSceneNodeIDs: [rootSceneNodeID]
    )
    let instanceID = try document.createComponentInstance(
        name: "Original",
        definitionID: definitionID
    )
    let secondOccurrenceID = try document.productMetadata.appendSceneNodeToFirstRoot(
        name: "Second occurrence",
        reference: .componentInstance(instanceID),
        object: .componentInstance(instanceID)
    )
    try document.productMetadata.validate(
        against: document.cadDocument,
        objectRegistry: .builtIn
    )

    let session = EditorSession(document: document)
    let firstOccurrenceID = try #require(
        session.document.productMetadata.sceneNodes.values.first {
            $0.reference?.componentInstanceID == instanceID && $0.id != secondOccurrenceID
        }?.id
    )
    let beforeFirst = try #require(session.document.productMetadata.sceneNodes[firstOccurrenceID])
    let beforeSecond = try #require(session.document.productMetadata.sceneNodes[secondOccurrenceID])

    let repairResult = try session.execute(
        .renameComponentInstance(id: instanceID, name: "  Original  ")
    )

    #expect(repairResult.didMutate)
    #expect(repairResult.generation == DocumentGeneration(1))
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.commandStack.undoEntries.count == 1)
    #expect(session.document.productMetadata.componentInstances[instanceID]?.name == "Original")
    #expect(session.document.productMetadata.sceneNodes[firstOccurrenceID]?.name == "Original")
    #expect(session.document.productMetadata.sceneNodes[secondOccurrenceID]?.name == "Original")

    let result = try session.execute(
        .renameComponentInstance(id: instanceID, name: "  Renamed Instance  ")
    )

    #expect(result.commandName == "renameComponentInstance")
    #expect(session.document.productMetadata.componentInstances[instanceID]?.name == "Renamed Instance")
    #expect(session.document.productMetadata.sceneNodes[firstOccurrenceID]?.name == "Renamed Instance")
    #expect(session.document.productMetadata.sceneNodes[secondOccurrenceID]?.name == "Renamed Instance")
    var expectedFirst = beforeFirst
    expectedFirst.name = "Renamed Instance"
    var expectedSecond = beforeSecond
    expectedSecond.name = "Renamed Instance"
    #expect(session.document.productMetadata.sceneNodes[firstOccurrenceID] == expectedFirst)
    #expect(session.document.productMetadata.sceneNodes[secondOccurrenceID] == expectedSecond)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func renameComponentInstanceWithConsistentNamesIsNoOp() throws {
    var document = DesignDocument.empty()
    let rootSceneNodeID = try #require(document.productMetadata.rootSceneNodeIDs.first)
    let definitionID = try document.createComponentDefinition(
        name: "Frame",
        rootSceneNodeIDs: [rootSceneNodeID]
    )
    let instanceID = try document.createComponentInstance(
        name: "Original",
        definitionID: definitionID
    )
    try document.productMetadata.validate(
        against: document.cadDocument,
        objectRegistry: .builtIn
    )

    let session = EditorSession(document: document)
    let beforeMetadata = session.document.productMetadata
    let beforeGeneration = session.generation
    let beforeTransactionRevision = session.transactionRevision
    let beforeEvaluationPassCount = session.store.completedEvaluationPassCount

    let result = try session.execute(
        .renameComponentInstance(id: instanceID, name: "  Original  ")
    )

    #expect(!result.didMutate)
    #expect(result.generation == beforeGeneration)
    #expect(session.generation == beforeGeneration)
    #expect(session.transactionRevision == beforeTransactionRevision)
    #expect(session.store.completedEvaluationPassCount == beforeEvaluationPassCount)
    #expect(!session.isDirty)
    #expect(session.commandStack.undoEntries.isEmpty)
    #expect(session.document.productMetadata == beforeMetadata)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func namingCommandsRejectComponentOccurrencesAndDuplicateNames() throws {
    var document = DesignDocument.empty()
    let rootSceneNodeID = try #require(document.productMetadata.rootSceneNodeIDs.first)
    let definitionID = try document.createComponentDefinition(
        name: "Frame",
        rootSceneNodeIDs: [rootSceneNodeID]
    )
    let firstInstanceID = try document.createComponentInstance(
        name: "First",
        definitionID: definitionID
    )
    let secondInstanceID = try document.createComponentInstance(
        name: "Second",
        definitionID: definitionID
    )
    let session = EditorSession(document: document)
    let firstSceneNodeID = try #require(
        session.document.productMetadata.sceneNodes.values.first {
            $0.reference?.componentInstanceID == firstInstanceID
        }?.id
    )
    let beforeMetadata = session.document.productMetadata
    let beforeGeneration = session.generation

    do {
        _ = try session.execute(.renameSceneNode(id: firstSceneNodeID, name: "Wrong owner"))
        Issue.record("Component occurrence rename unexpectedly succeeded through SceneNode owner.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
    }
    #expect(session.document.productMetadata == beforeMetadata)
    #expect(session.generation == beforeGeneration)

    do {
        _ = try session.execute(
            .renameComponentInstance(id: firstInstanceID, name: "  Second  ")
        )
        Issue.record("Duplicate component instance rename unexpectedly succeeded.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
    }
    #expect(session.document.productMetadata == beforeMetadata)
    #expect(session.generation == beforeGeneration)
    #expect(session.document.productMetadata.componentInstances[secondInstanceID]?.name == "Second")

    do {
        _ = try session.execute(.renameSceneNode(id: rootSceneNodeID, name: "   "))
        Issue.record("Empty scene node name unexpectedly succeeded.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
    }
    #expect(session.document.productMetadata == beforeMetadata)
    #expect(session.generation == beforeGeneration)

    do {
        _ = try session.execute(.renameComponentInstance(id: firstInstanceID, name: "   "))
        Issue.record("Empty component instance name unexpectedly succeeded.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
    }
    #expect(session.document.productMetadata == beforeMetadata)
    #expect(session.generation == beforeGeneration)

    do {
        _ = try session.execute(.renameSceneNode(id: SceneNodeID(), name: "Missing"))
        Issue.record("Missing scene node rename unexpectedly succeeded.")
    } catch let error as EditorError {
        #expect(error.code == .referenceUnresolved)
    }
    #expect(session.document.productMetadata == beforeMetadata)
    #expect(session.generation == beforeGeneration)

    do {
        _ = try session.execute(.renameComponentInstance(id: ComponentInstanceID(), name: "Missing"))
        Issue.record("Missing component instance rename unexpectedly succeeded.")
    } catch let error as EditorError {
        #expect(error.code == .referenceUnresolved)
    }
    #expect(session.document.productMetadata == beforeMetadata)
    #expect(session.generation == beforeGeneration)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func renameSceneNodeRejectsSavedConstructionPlaneOwnership() throws {
    let session = EditorSession()
    let creationResult = try #require(
        session.createConstructionPlane(name: "Saved Plane", plane: .xy)
    )
    let planeID = try #require(creationResult.createdConstructionPlaneID)
    let sceneNodeID = try #require(
        session.document.productMetadata.sceneNodes.values.first {
            $0.reference?.constructionPlaneID == planeID
        }?.id
    )
    let beforeMetadata = session.document.productMetadata
    let beforeGeneration = session.generation
    let beforeTransactionRevision = session.transactionRevision
    let beforeEvaluationPassCount = session.store.completedEvaluationPassCount
    let beforeUndoCount = session.commandStack.undoEntries.count

    do {
        _ = try session.execute(
            .renameSceneNode(id: sceneNodeID, name: "Wrong owner")
        )
        Issue.record("Saved construction plane rename unexpectedly bypassed its source owner.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
    }

    #expect(session.document.productMetadata == beforeMetadata)
    #expect(session.generation == beforeGeneration)
    #expect(session.transactionRevision == beforeTransactionRevision)
    #expect(session.store.completedEvaluationPassCount == beforeEvaluationPassCount)
    #expect(session.commandStack.undoEntries.count == beforeUndoCount)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func patternArrayNamesRemainOwnedByTheirSource() throws {
    let session = try patternNamingSession()
    let source = try #require(session.document.productMetadata.patternArrays.values.first)
    let outputSceneNodeID = try #require(
        session.document.productMetadata.sceneNodes[source.rootSceneNodeID]?.childIDs.first
    )
    let beforeMetadata = session.document.productMetadata
    let beforeGeneration = session.generation

    do {
        _ = try session.execute(
            .renameSceneNode(id: source.rootSceneNodeID, name: "Wrong root name")
        )
        Issue.record("Pattern root rename unexpectedly bypassed the source owner.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
    }
    do {
        _ = try session.execute(
            .renameSceneNode(id: outputSceneNodeID, name: "Wrong output name")
        )
        Issue.record("Generated output rename unexpectedly bypassed the source owner.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
    }
    let outputInstanceID = try #require(source.outputInstanceIDs.first)
    do {
        _ = try session.execute(
            .renameComponentInstance(id: outputInstanceID, name: "Wrong output instance name")
        )
        Issue.record("Generated pattern component instance rename unexpectedly succeeded.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
    }
    #expect(session.document.productMetadata == beforeMetadata)
    #expect(session.generation == beforeGeneration)

    let updateResult = try session.execute(
        .updatePatternArray(
            id: source.id,
            name: "  Renamed Pattern  ",
            definitionID: nil,
            distribution: nil,
            outputMode: nil
        )
    )
    let renamedSource = try #require(session.document.productMetadata.patternArrays[source.id])
    let renamedRoot = try #require(
        session.document.productMetadata.sceneNodes[renamedSource.rootSceneNodeID]
    )
    #expect(updateResult.commandName == "updatePatternArray")
    #expect(updateResult.didMutate)
    #expect(renamedSource.name == "Renamed Pattern")
    #expect(renamedRoot.name == "Renamed Pattern")
    #expect(renamedSource.rootSceneNodeID == source.rootSceneNodeID)
}

private func patternNamingSession() throws -> EditorSession {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(
        session.document.productMetadata.sceneNodes.values.first {
            $0.reference?.featureID == bodyFeatureID
        }?.id
    )
    let definitionResult = try session.execute(
        .createComponentDefinition(
            name: "Pattern Source",
            rootSceneNodeIDs: [bodySceneNodeID]
        )
    )
    let definitionID = try #require(definitionResult.generatedIdentities.componentDefinitionIDs.first)
    _ = try session.execute(
        .createPatternArray(
            name: "Pattern",
            definitionID: definitionID,
            distribution: .rectangular(
                RectangularPatternArray(
                    firstAxis: PatternArrayLinearAxis(
                        direction: .unitX,
                        distance: .length(10, .millimeter),
                        copyCount: 1
                    )
                )
            ),
            outputMode: .componentInstance
        )
    )
    return session
}
