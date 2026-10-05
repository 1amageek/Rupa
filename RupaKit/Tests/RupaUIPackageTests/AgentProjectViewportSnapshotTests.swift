import Foundation
import RupaAgentProtocol
@testable import RupaAgentRuntime
import RupaCore
import RupaCoreTypes
import RupaGeometry
@testable import RupaKit
import RupaProject
import Testing

@MainActor
@Test(.timeLimit(.minutes(1)))
func projectAgentViewportReadPreservesLiteralNativeSceneIdentityWire() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    var document = session.document
    let originalID = try #require(document.productMetadata.sceneNodes.first {
        $0.value.reference?.kind == .body
    }?.key)
    let literalID = SceneNodeID(UUID(uuid: (
        0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x46, 0x77,
        0x88, 0x99, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF
    )))
    var node = try #require(document.productMetadata.sceneNodes.removeValue(forKey: originalID))
    node.id = literalID
    document.productMetadata.sceneNodes[literalID] = node
    document.productMetadata.rootSceneNodeIDs = document.productMetadata.rootSceneNodeIDs.map {
        $0 == originalID ? literalID : $0
    }
    for id in Array(document.productMetadata.sceneNodes.keys) {
        var existing = try #require(document.productMetadata.sceneNodes[id])
        existing.childIDs = existing.childIDs.map {
            $0 == originalID ? literalID : $0
        }
        document.productMetadata.sceneNodes[id] = existing
    }
    let workspace = try DefaultProjectWorkspaceFactory().makeWorkspace(document: document)
    _ = try await workspace.evaluate()
    let controller = ProjectAgentCommandController(semanticProgramCompiler: try projectAgentSemanticCompiler())
    let sessionID = try await controller.register(workspace: workspace)
    let published = try #require(workspace.view)
    let response = await controller.projectAgentHandle(.viewportSnapshot(
        sessionID: sessionID, expectedGeneration: published.documentGeneration
    ))
    guard case .viewportSnapshot(let snapshot) = response else {
        Issue.record("Expected the actual published viewport projection.")
        return
    }
    let item = try #require(snapshot.items.first { $0.sceneNodeID == literalID })
    let wire = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as? [String: Any])
    #expect(wire["sceneNodeID"] as? String == "00112233-4455-4677-8899-AABBCCDDEEFF")
    #expect(workspace.view?.publicationSequence == published.publicationSequence)
    #expect(snapshot.coordinates.documentGeneration == published.documentGeneration)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func projectAgentViewportReadUsesTheExactPublishedViewportAndRejectsStaleGeneration() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    _ = try #require(session.createDefaultExtrudedRectangle())
    let workspace = try DefaultProjectWorkspaceFactory().makeWorkspace(
        document: session.document
    )
    _ = try await workspace.evaluate()
    let controller = ProjectAgentCommandController(semanticProgramCompiler: try projectAgentSemanticCompiler())
    let sessionID = try await controller.register(workspace: workspace)
    let published = try #require(workspace.view)

    let response = await controller.projectAgentHandle(
        .viewportSnapshot(
            sessionID: sessionID,
            expectedGeneration: published.documentGeneration
        )
    )
    guard case .viewportSnapshot(let snapshot) = response else {
        Issue.record("Expected the production Agent controller to return the project viewport.")
        return
    }

    let expectedItems = published.viewport.items.sorted {
        $0.occurrenceID.rawValue < $1.occurrenceID.rawValue
    }
    #expect(snapshot.coordinates.sessionID == sessionID)
    #expect(snapshot.coordinates.projectID == published.projectID)
    #expect(snapshot.coordinates.documentGeneration == published.documentGeneration)
    #expect(snapshot.coordinates.transactionRevision == published.transactionRevision)
    #expect(snapshot.coordinates.publicationSequence == published.publicationSequence)
    #expect(snapshot.coordinates.workspaceRevision == published.workspaceState.revision)
    #expect(snapshot.evaluationSnapshotID == published.viewport.snapshotID)
    #expect(snapshot.worldBounds == published.viewport.worldBounds)
    #expect(snapshot.copyTelemetry == published.viewport.copyTelemetry)
    #expect(snapshot.items.map(\.occurrenceID) == expectedItems.map(\.occurrenceID))
    #expect(snapshot.items.count == expectedItems.count)

    var expectedTriangleCount: UInt64 = 0
    for (item, expected) in zip(snapshot.items, expectedItems) {
        #expect(item.sceneNodeID == published.sceneNodeID(for: expected.occurrenceID))
        #expect(item.definitionID == expected.definitionID)
        #expect(item.displayName == expected.displayName)
        #expect(item.representationID == expected.representationID)
        #expect(item.sourceReference == expected.sourceReference)
        #expect(item.worldTransform == expected.worldTransform)
        #expect(item.worldBounds == expected.worldBounds)
        #expect(item.vertexCount == UInt64(expected.mesh.vertexIDs.count))
        #expect(item.faceCount == UInt64(expected.mesh.faceIDs.count))
        #expect(item.cornerCount == UInt64(expected.mesh.cornerIDs.count))
        let expectedItemTriangleCount = try expected.mesh.triangulatedTriangleCount()
        #expect(item.triangleCount == expectedItemTriangleCount)
        expectedTriangleCount += expectedItemTriangleCount
    }
    #expect(snapshot.triangleCount == expectedTriangleCount)

    let stale = await controller.projectAgentHandle(
        .viewportSnapshot(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(published.documentGeneration.value + 1)
        )
    )
    guard case .failure(let error) = stale else {
        Issue.record("Expected a typed stale-generation failure.")
        return
    }
    #expect(error.code == .documentGenerationMismatch)
    #expect(workspace.view?.publicationSequence == published.publicationSequence)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func projectViewportProjectionRejectsMissingNavigation() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let workspace = try DefaultProjectWorkspaceFactory().makeWorkspace(
        document: session.document
    )
    _ = try await workspace.evaluate()
    let published = try #require(workspace.view)
    let invalidNavigation = ProjectViewSnapshot(
        documentLifetimeID: published.documentLifetimeID,
        projectID: published.projectID,
        projectName: published.projectName,
        document: published.document,
        documentGeneration: published.documentGeneration,
        transactionRevision: published.transactionRevision,
        publicationSequence: published.publicationSequence,
        isDirty: published.isDirty,
        canUndo: published.canUndo,
        canRedo: published.canRedo,
        selection: published.selection,
        workspaceState: published.workspaceState,
        objectRegistry: published.objectRegistry,
        evaluationSnapshot: published.evaluationSnapshot,
        viewport: published.viewport,
        cadInteraction: published.cadInteraction,
        sceneNodeIDByOccurrenceID: [:],
        retiredObjectProperties: published.retiredObjectProperties
    )

    do {
        _ = try ProjectAgentGeometryProjection.viewportSnapshot(
            sessionID: UUID(),
            view: invalidNavigation
        )
        Issue.record("Expected missing viewport navigation to fail.")
    } catch let error as EditorError {
        #expect(error.code == .referenceUnresolved)
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func projectViewportProjectionRejectsAggregateResourceLimitsWithoutPartialOutput() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    _ = try #require(session.createDefaultExtrudedRectangle())
    let workspace = try DefaultProjectWorkspaceFactory().makeWorkspace(
        document: session.document
    )
    _ = try await workspace.evaluate()
    let published = try #require(workspace.view)

    do {
        _ = try ProjectAgentGeometryProjection.viewportSnapshot(
            sessionID: UUID(),
            view: published,
            limits: ProjectAgentViewportSnapshotLimits(
                maxItems: 1,
                maxElementRecords: 1_048_576,
                maxAuxiliaryRecords: 4_096,
                maxTriangleCount: 1_048_576,
                maxStringUTF8Bytes: 1_048_576
            )
        )
        Issue.record("Expected the viewport item ceiling to reject the whole result.")
    } catch let error as ProjectMeshReadError {
        #expect(error.code == .limitExceeded)
    }

    do {
        _ = try ProjectAgentGeometryProjection.viewportSnapshot(
            sessionID: UUID(),
            view: published,
            limits: ProjectAgentViewportSnapshotLimits(
                maxItems: 4_096,
                maxElementRecords: 1,
                maxAuxiliaryRecords: 4_096,
                maxTriangleCount: 1_048_576,
                maxStringUTF8Bytes: 1_048_576
            )
        )
        Issue.record("Expected the viewport work ceiling to reject the whole result.")
    } catch let error as ProjectMeshReadError {
        #expect(error.code == .limitExceeded)
    }

    do {
        _ = try ProjectAgentGeometryProjection.viewportSnapshot(
            sessionID: UUID(),
            view: published,
            limits: ProjectAgentViewportSnapshotLimits(
                maxItems: 4_096,
                maxElementRecords: 1_048_576,
                maxAuxiliaryRecords: 4_096,
                maxTriangleCount: 1,
                maxStringUTF8Bytes: 1_048_576
            )
        )
        Issue.record("Expected the viewport triangle ceiling to reject the whole result.")
    } catch let error as ProjectMeshReadError {
        #expect(error.code == .limitExceeded)
    }

    do {
        _ = try ProjectAgentGeometryProjection.viewportSnapshot(
            sessionID: UUID(),
            view: published,
            limits: ProjectAgentViewportSnapshotLimits(
                maxItems: 4_096,
                maxElementRecords: 1_048_576,
                maxAuxiliaryRecords: 4_096,
                maxTriangleCount: 1_048_576,
                maxStringUTF8Bytes: 1
            )
        )
        Issue.record("Expected the viewport string ceiling to reject the whole result.")
    } catch let error as ProjectMeshReadError {
        #expect(error.code == .limitExceeded)
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func projectViewportProjectionPropagatesItsOperationGuard() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let workspace = try DefaultProjectWorkspaceFactory().makeWorkspace(
        document: session.document
    )
    _ = try await workspace.evaluate()
    let published = try #require(workspace.view)

    do {
        _ = try ProjectAgentGeometryProjection.viewportSnapshot(
            sessionID: UUID(),
            view: published,
            operationGuard: {
                throw CancellationError()
            }
        )
        Issue.record("Expected the viewport projection operation guard to cancel the read.")
    } catch is CancellationError {
        #expect(workspace.view?.publicationSequence == published.publicationSequence)
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func projectAgentViewportReadOmitsHiddenItemsWithoutDroppingEvaluationAuthority() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let workspace = try DefaultProjectWorkspaceFactory().makeWorkspace(
        document: session.document
    )
    _ = try await workspace.evaluate()
    let controller = ProjectAgentCommandController(semanticProgramCompiler: try projectAgentSemanticCompiler())
    let sessionID = try await controller.register(workspace: workspace)
    let visible = try #require(workspace.view)
    let visibleItem = try #require(visible.viewport.items.first)
    let sceneNodeID = try #require(visible.sceneNodeID(for: visibleItem.occurrenceID))

    let hidden = try await workspace.commit(
        ProjectSourceTransaction(
            name: "agent.viewport.hide",
            commands: [
                .setSceneNodeVisibility(id: sceneNodeID, isVisible: false),
            ],
            expectedProjectID: visible.projectID,
            expectedTransactionRevision: visible.transactionRevision,
            expectedPublicationSequence: visible.publicationSequence
        )
    )
    let response = await controller.projectAgentHandle(
        .viewportSnapshot(
            sessionID: sessionID,
            expectedGeneration: hidden.documentGeneration
        )
    )
    guard case .viewportSnapshot(let snapshot) = response else {
        Issue.record("Expected the hidden project viewport snapshot.")
        return
    }
    let state = try await workspace.projectAuthorityOwner.currentState()

    #expect(snapshot.coordinates.publicationSequence == hidden.publicationSequence)
    #expect(snapshot.items.isEmpty)
    #expect(snapshot.triangleCount == 0)
    #expect(snapshot.worldBounds == nil)
    #expect(state.evaluation.occurrences[visibleItem.occurrenceID] != nil)
    #expect(state.evaluationSource.occurrences[visibleItem.occurrenceID] != nil)
    #expect(hidden.sceneNodeID(for: visibleItem.occurrenceID) == sceneNodeID)
}
