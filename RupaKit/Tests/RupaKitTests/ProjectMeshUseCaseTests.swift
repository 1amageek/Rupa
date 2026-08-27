import Foundation
import RupaCore
import RupaCoreTypes
import RupaKit
import RupaProject
import RupaProjectModel
import SwiftCAD
import Synchronization
import Testing
@testable import RupaGeometry

@Test(.timeLimit(.minutes(1)))
func projectMeshCatalogReportsSourcesReferencesBoundsAndStableOrder() async throws {
    let document = try projectMeshUseCaseMeshOnlyDocument(named: "Catalog")
    let asset = try #require(document.authoredMeshAssets.values.first)
    let controller = try projectMeshUseCaseController(document: document)
    let workspace = await ProjectWorkspace(project: controller)
    let view = try await workspace.evaluate()

    let catalog = try await workspace.catalog(from: view)
    let source = try #require(catalog.source(for: asset.id))
    let node = try #require(view.document.document.productMetadata.sceneNodes.values.first {
        $0.object?.geometryRole == .mesh
    })
    let selection = try #require(node.object?.geometryRepresentations.selection)
    let references = source.references

    #expect(catalog.projectAuthorityCoordinate.projectID == view.projectID)
    #expect(catalog.projectAuthorityCoordinate.transactionRevision == view.transactionRevision)
    #expect(catalog.projectAuthorityCoordinate.publicationSequence == view.publicationSequence)
    #expect(source.handle.sourceID == asset.id)
    #expect(source.handle.contentIdentity == asset.contentIdentity)
    #expect(source.provenance == .created)
    #expect(source.counts == ProjectMeshElementCounts(vertices: 3, edges: 3, faces: 1, corners: 3))
    #expect(source.bounds?.minimum == GeometryPoint3D(x: 0, y: 0, z: 0))
    #expect(source.bounds?.maximum == GeometryPoint3D(x: 1, y: 1, z: 0))
    let evaluatedMesh = try #require(view.viewport.items.first?.mesh)
    #expect(evaluatedMesh.vertexPositions.storage.chunkIdentities == asset.source.vertexPositions.storage.chunkIdentities)
    #expect(evaluatedMesh.cornerVertexIDs.storage.chunkIdentities == asset.source.cornerVertexIDs.storage.chunkIdentities)
    #expect(references.count == 1)
    #expect(references.allSatisfy { $0.sceneNodeID == node.id })
    #expect(references[0].representationID == selection.modeling)
    #expect(references[0].selectedPurposes == [.modeling, .presentation])
}

@Test(.timeLimit(.minutes(1)))
func projectMeshPagesReturnAllDomainsAndRejectBoundCursor() async throws {
    let document = try projectMeshUseCaseMeshOnlyDocument(named: "Pages")
    let asset = try #require(document.authoredMeshAssets.values.first)
    let controller = try projectMeshUseCaseController(document: document)
    let workspace = await ProjectWorkspace(project: controller)
    let view = try await workspace.evaluate()
    let source = try #require(view.document.document.authoredMeshAssets[asset.id]?.source)
    let pageLimits = ProjectMeshReadLimits(maxPageRecords: 1, maxOutputRecords: 1)

    for domain in ProjectMeshElementDomain.allCases {
        let page = try await workspace.page(
            ProjectMeshElementPageRequest(
                handle: ProjectMeshSourceHandle(
                    projectAuthorityCoordinate: projectMeshCoordinate(from: view),
                    sourceID: asset.id,
                    contentIdentity: asset.contentIdentity
                ),
                domain: domain,
                limits: pageLimits
            ),
            from: view
        )
        #expect(page.domain == domain)
        #expect(page.records.count == 1)
        #expect(page.records[0].domain == domain)
        switch page.records[0] {
        case .vertex(let record):
            #expect(record.id == source.vertexIDs[0])
            #expect(record.position == source.vertexPositions[0])
        case .edge(let record):
            #expect(record.id == source.edgeIDs[0])
            #expect(record.endpoints == source.edgeEndpoints[0])
        case .face(let record):
            let range = source.faceCornerRanges[0]
            #expect(record.id == source.faceIDs[0])
            #expect(record.cornerIDs == Array(source.cornerIDs[range.start..<range.end]))
        case .corner(let record):
            #expect(record.id == source.cornerIDs[0])
            #expect(record.vertexID == source.cornerVertexIDs[0])
            #expect(record.edgeID == source.cornerEdgeIDs[0])
            #expect(record.faceID == source.faceIDs[0])
            #expect(record.previousID == source.cornerIDs[2])
            #expect(record.nextID == source.cornerIDs[1])
        }
    }

    let handle = ProjectMeshSourceHandle(
        projectAuthorityCoordinate: projectMeshCoordinate(from: view),
        sourceID: asset.id,
        contentIdentity: asset.contentIdentity
    )
    let first = try await workspace.page(
        ProjectMeshElementPageRequest(
            handle: handle,
            domain: .vertex,
            limits: pageLimits
        ),
        from: view
    )
    let cursor = try #require(first.nextCursor)
    let second = try await workspace.page(
        ProjectMeshElementPageRequest(
            handle: handle,
            domain: .vertex,
            cursor: cursor,
            limits: pageLimits
        ),
        from: view
    )
    #expect(first.records[0].reference != second.records[0].reference)

    let mismatchedCursor = ProjectMeshElementCursor(
        sourceID: asset.id,
        contentIdentity: try projectMeshAlternateContentIdentity(),
        domain: .vertex,
        nextIndex: 1
    )
    var cursorError: ProjectMeshReadError?
    do {
        _ = try await workspace.page(
            ProjectMeshElementPageRequest(
                handle: handle,
                domain: .vertex,
                cursor: mismatchedCursor,
                limits: pageLimits
            ),
            from: view
        )
    } catch let error as ProjectMeshReadError {
        cursorError = error
    }
    #expect(cursorError?.code == .invalidCursor)

    let mismatchedHandle = ProjectMeshSourceHandle(
        projectAuthorityCoordinate: projectMeshCoordinate(from: view),
        sourceID: asset.id,
        contentIdentity: try projectMeshAlternateContentIdentity()
    )
    var sourceIdentityError: ProjectMeshReadError?
    do {
        _ = try await workspace.page(
            ProjectMeshElementPageRequest(
                handle: mismatchedHandle,
                domain: .vertex,
                limits: pageLimits
            ),
            from: view
        )
    } catch let error as ProjectMeshReadError {
        sourceIdentityError = error
    }
    #expect(sourceIdentityError?.code == .sourceIdentityMismatch)
    #expect(source.vertexIDs.count == 3)
}

@Test(.timeLimit(.minutes(1)))
func projectMeshNeighborhoodUsesBoundedBreadthFirstTopology() async throws {
    let document = try projectMeshUseCaseMeshOnlyDocument(named: "Neighborhood")
    let asset = try #require(document.authoredMeshAssets.values.first)
    let controller = try projectMeshUseCaseController(document: document)
    let workspace = await ProjectWorkspace(project: controller)
    let view = try await workspace.evaluate()
    let source = try #require(view.document.document.authoredMeshAssets[asset.id]?.source)
    let handle = ProjectMeshSourceHandle(
        projectAuthorityCoordinate: projectMeshCoordinate(from: view),
        sourceID: asset.id,
        contentIdentity: asset.contentIdentity
    )

    let neighborhood = try await workspace.neighborhood(
        ProjectMeshNeighborhoodRequest(
            handle: handle,
            origin: .vertex(try #require(source.vertexIDs.first)),
            depth: 1
        ),
        from: view
    )

    #expect(neighborhood.records.first?.distance == 0)
    #expect(neighborhood.records.first?.element.reference == .vertex(source.vertexIDs[0]))
    #expect(neighborhood.records.allSatisfy { $0.distance <= 1 })
    #expect(neighborhood.records.contains { $0.element.domain == .edge })
    #expect(neighborhood.records.contains { $0.element.domain == .corner })
    #expect(neighborhood.records.contains { $0.element.domain == .face } == false)
    for pair in zip(neighborhood.records, neighborhood.records.dropFirst()) {
        #expect(pair.0.distance <= pair.1.distance)
        if pair.0.distance == pair.1.distance {
            #expect(pair.0.element.domain.sortOrderForTesting <= pair.1.element.domain.sortOrderForTesting)
        }
    }
}

@Test(.timeLimit(.minutes(1)))
func projectMeshReadLimitsRejectDepthScanOutputAndReferenceOverflow() async throws {
    let document = try projectMeshUseCaseMeshOnlyDocument(named: "Limits")
    let asset = try #require(document.authoredMeshAssets.values.first)
    let controller = try projectMeshUseCaseController(document: document)
    let workspace = await ProjectWorkspace(project: controller)
    let view = try await workspace.evaluate()
    let source = try #require(view.document.document.authoredMeshAssets[asset.id]?.source)
    let handle = ProjectMeshSourceHandle(
        projectAuthorityCoordinate: projectMeshCoordinate(from: view),
        sourceID: asset.id,
        contentIdentity: asset.contentIdentity
    )

    var depthError: ProjectMeshReadError?
    do {
        _ = try await workspace.neighborhood(
            ProjectMeshNeighborhoodRequest(
                handle: handle,
                origin: .vertex(source.vertexIDs[0]),
                depth: 2,
                limits: ProjectMeshReadLimits(maxNeighborhoodDepth: 1)
            ),
            from: view
        )
    } catch let error as ProjectMeshReadError {
        depthError = error
    }
    #expect(depthError?.code == .limitExceeded)

    var outputError: ProjectMeshReadError?
    do {
        _ = try await workspace.neighborhood(
            ProjectMeshNeighborhoodRequest(
                handle: handle,
                origin: .vertex(source.vertexIDs[0]),
                depth: 1,
                limits: ProjectMeshReadLimits(maxOutputRecords: 1)
            ),
            from: view
        )
    } catch let error as ProjectMeshReadError {
        outputError = error
    }
    #expect(outputError?.code == .limitExceeded)

    var scanError: ProjectMeshReadError?
    do {
        _ = try await workspace.neighborhood(
            ProjectMeshNeighborhoodRequest(
                handle: handle,
                origin: .vertex(source.vertexIDs[0]),
                depth: 1,
                limits: ProjectMeshReadLimits(maxScannedRecords: 1)
            ),
            from: view
        )
    } catch let error as ProjectMeshReadError {
        scanError = error
    }
    #expect(scanError?.code == .limitExceeded)

    var referenceError: ProjectMeshReadError?
    do {
        _ = try await workspace.page(
            ProjectMeshElementPageRequest(
                handle: handle,
                domain: .edge,
                limits: ProjectMeshReadLimits(maxReferenceUnits: 1)
            ),
            from: view
        )
    } catch let error as ProjectMeshReadError {
        referenceError = error
    }
    #expect(referenceError?.code == .limitExceeded)

    var invalidError: ProjectMeshReadError?
    do {
        _ = try await workspace.catalog(
            from: view,
            limits: ProjectMeshReadLimits(maxOutputRecords: 0)
        )
    } catch let error as ProjectMeshReadError {
        invalidError = error
    }
    #expect(invalidError?.code == .invalidLimit)

    var hardCeilingError: ProjectMeshReadError?
    do {
        _ = try await workspace.catalog(
            from: view,
            limits: ProjectMeshReadLimits(
                maxSources: ProjectMeshReadLimits.hard.maxSources + 1
            )
        )
    } catch let error as ProjectMeshReadError {
        hardCeilingError = error
    }
    #expect(hardCeilingError?.code == .limitExceeded)
}

@Test(.timeLimit(.minutes(1)))
func projectMeshReadsRejectStaleCoordinatesAndCancellationBeforeAndAfterWork() async throws {
    let document = try projectMeshUseCaseMeshOnlyDocument(named: "Stale Reads")
    let asset = try #require(document.authoredMeshAssets.values.first)
    let controller = try projectMeshUseCaseController(document: document)
    let workspace = await ProjectWorkspace(project: controller)
    let initial = try await workspace.evaluate()
    let handle = ProjectMeshSourceHandle(
        projectAuthorityCoordinate: projectMeshCoordinate(from: initial),
        sourceID: asset.id,
        contentIdentity: asset.contentIdentity
    )

    _ = try await controller.evaluateCurrent()

    var staleError: ProjectMeshReadError?
    do {
        _ = try await workspace.page(
            ProjectMeshElementPageRequest(handle: handle, domain: .vertex),
            from: initial
        )
    } catch let error as ProjectMeshReadError {
        staleError = error
    }
    #expect(staleError?.code == .publicationSequenceMismatch)

    let current = try await workspace.refresh()
    let guardCallCount = Mutex(0)
    let mutationTask = Mutex<Task<Void, Never>?>(nil)
    let mutationFinished = Mutex(false)
    let mutationSucceeded = Mutex(false)
    let postReadStaleGuard: ProjectOperationGuard = {
        let count = guardCallCount.withLock {
            $0 += 1
            return $0
        }
        if count == 3 {
            while !mutationFinished.withLock({ $0 }) {
                Thread.sleep(forTimeInterval: 0.001)
            }
            return
        }
        guard count == 2 else {
            return
        }
        let task = Task {
            defer {
                mutationFinished.withLock { $0 = true }
            }
            do {
                _ = try await controller.evaluateCurrent()
                mutationSucceeded.withLock { $0 = true }
            } catch {
                return
            }
        }
        mutationTask.withLock {
            $0 = task
        }
    }
    var postReadError: ProjectMeshReadError?
    do {
        _ = try await workspace.catalog(
            from: current,
            operationGuard: postReadStaleGuard
        )
    } catch let error as ProjectMeshReadError {
        postReadError = error
    }
    if let task = mutationTask.withLock({ $0 }) {
        await task.value
    }
    #expect(mutationSucceeded.withLock { $0 })
    #expect(postReadError?.code == .publicationSequenceMismatch)

    let cancellationGuard: ProjectOperationGuard = {
        throw CancellationError()
    }
    var cancellationError: ProjectMeshReadError?
    do {
        _ = try await workspace.catalog(
            from: current,
            operationGuard: cancellationGuard
        )
    } catch let error as ProjectMeshReadError {
        cancellationError = error
    }
    #expect(cancellationError?.code == .cancelled)
}

@Test(.timeLimit(.minutes(1)))
func projectMeshPreviewDoesNotPublishSourceViewPackageOrHistory() async throws {
    let document = try projectMeshUseCaseMeshOnlyDocument(named: "Preview")
    let asset = try #require(document.authoredMeshAssets.values.first)
    let controller = try projectMeshUseCaseController(document: document)
    let workspace = await ProjectWorkspace(project: controller)
    let view = try await workspace.evaluate()
    let stateBefore = try await controller.currentState()
    let plan = try projectMeshUseCasePlan(vertexID: asset.source.vertexIDs[0], z: 3)
    let request = ProjectMeshEditRequest(
        handle: ProjectMeshSourceHandle(
            projectAuthorityCoordinate: projectMeshCoordinate(from: view),
            sourceID: asset.id,
            contentIdentity: asset.contentIdentity
        ),
        plan: plan,
        snapshot: view
    )

    let preview = try await workspace.preview(request)
    let retainedView = try #require(await workspace.view)
    let retainedState = try await controller.currentState()

    #expect(preview.baseSnapshot.projectID == view.projectID)
    #expect(preview.sourceID == asset.id)
    #expect(preview.previousContentIdentity == asset.contentIdentity)
    #expect(preview.proposedContentIdentity != asset.contentIdentity)
    #expect(preview.didMutate)
    #expect(retainedView.transactionRevision == view.transactionRevision)
    #expect(retainedView.publicationSequence == view.publicationSequence)
    #expect(retainedState.transactionRevision == stateBefore.transactionRevision)
    #expect(retainedState.publicationSequence == stateBefore.publicationSequence)
    #expect(retainedState.canUndo == stateBefore.canUndo)
    #expect(retainedState.document.authoredMeshAssets[asset.id] == asset)
    #expect(retainedState.package.authoredMeshAssets[asset.id] == asset)
}

@Test(.timeLimit(.minutes(1)))
func projectMeshCommitPublishesExactViewNewHandleAndOneUndoEntry() async throws {
    let document = try projectMeshUseCaseMeshOnlyDocument(named: "Commit")
    let asset = try #require(document.authoredMeshAssets.values.first)
    let controller = try projectMeshUseCaseController(document: document)
    let workspace = await ProjectWorkspace(project: controller)
    let initial = try await workspace.evaluate()
    let request = ProjectMeshEditRequest(
        handle: ProjectMeshSourceHandle(
            projectAuthorityCoordinate: projectMeshCoordinate(from: initial),
            sourceID: asset.id,
            contentIdentity: asset.contentIdentity
        ),
        plan: try projectMeshUseCasePlan(vertexID: asset.source.vertexIDs[0], z: 4),
        snapshot: initial
    )

    let committed = try await workspace.commit(request)
    let state = try await controller.currentState()
    let committedAsset = try #require(state.document.authoredMeshAssets[asset.id])

    #expect(committed.sourceID == asset.id)
    #expect(committed.previousContentIdentity == asset.contentIdentity)
    #expect(committed.contentIdentity == committedAsset.contentIdentity)
    #expect(committed.handle.contentIdentity == committedAsset.contentIdentity)
    #expect(committed.receipt.didChange)
    #expect(committed.receipt.stepReceipts.count == 1)
    #expect(committed.handle.projectAuthorityCoordinate == projectMeshCoordinate(from: committed.view))
    #expect(committed.view.transactionRevision.value == initial.transactionRevision.value + 1)
    #expect(committed.view.documentGeneration.value == initial.documentGeneration.value + 1)
    #expect(state.transactionRevision == committed.view.transactionRevision)
    #expect(state.publicationSequence == committed.view.publicationSequence)
    #expect(state.canUndo)
    #expect(await workspace.view?.publicationSequence == committed.view.publicationSequence)
    #expect(committed.view.document.document.authoredMeshAssets[asset.id] == committedAsset)

    let undone = try await workspace.undo(from: committed.view)
    let restored = try await controller.currentState()
    #expect(restored.document.authoredMeshAssets[asset.id] == asset)
    #expect(undone.document.document.authoredMeshAssets[asset.id] == asset)
    #expect(undone.canUndo == false)
    #expect(undone.canRedo)
    #expect(undone.transactionRevision.value == committed.view.transactionRevision.value + 1)
}

@Test(.timeLimit(.minutes(1)))
func projectMeshEditingRejectsStaleHandleAndPreservesCADMeshRouting() async throws {
    let document = try projectMeshUseCaseCADAndMeshDocument(named: "Mixed")
    let asset = try #require(document.authoredMeshAssets.values.first)
    let body = try #require(document.productMetadata.sceneNodes.values.first { $0.object?.category == .body })
    let cadRepresentationID = try #require(body.object?.geometryRepresentations.selection?.modeling)
    let meshRepresentationID = try #require(body.object?.geometryRepresentations.selection?.presentation)
    let controller = try projectMeshUseCaseController(document: document)
    let workspace = await ProjectWorkspace(project: controller)
    let initial = try await workspace.evaluate()
    let catalog = try await workspace.catalog(from: initial)
    let catalogSource = try #require(catalog.source(for: asset.id))
    let request = ProjectMeshEditRequest(
        handle: catalogSource.handle,
        plan: try projectMeshUseCasePlan(vertexID: asset.source.vertexIDs[0], z: 5),
        snapshot: initial
    )

    #expect(initial.document.hasAuthoritativeCADSource)
    #expect(catalogSource.references.count == 1)
    #expect(catalogSource.references[0].selectedPurposes == [.presentation])

    let committed = try await workspace.commit(request)
    let published = await controller.currentDocument()
    let publishedBody = try #require(published.productMetadata.sceneNodes.values.first { $0.object?.category == .body })
    let publishedSelection = try #require(publishedBody.object?.geometryRepresentations.selection)
    #expect(published.hasAuthoritativeCADSource)
    #expect(publishedSelection.modeling == cadRepresentationID)
    #expect(publishedSelection.presentation == meshRepresentationID)

    var staleError: ProjectMeshEditError?
    do {
        _ = try await workspace.commit(request)
    } catch let error as ProjectMeshEditError {
        staleError = error
    }
    #expect(staleError?.code == .transactionRevisionMismatch)
    #expect(await controller.currentTransactionRevision() == committed.view.transactionRevision)
}

@Test(.timeLimit(.minutes(1)))
func projectMeshCommitPreservesPostCommitNoRetryFailure() async throws {
    let document = try projectMeshUseCaseMeshOnlyDocument(named: "Post Commit")
    let asset = try #require(document.authoredMeshAssets.values.first)
    let controller = try projectMeshUseCaseController(document: document)
    let buildCount = Mutex(0)
    let workspace = await ProjectWorkspace(
        project: controller,
        viewBuilder: ProjectMeshFailingViewBuilder(failingBuild: 2, count: buildCount)
    )
    let initial = try await workspace.evaluate()
    let request = ProjectMeshEditRequest(
        handle: ProjectMeshSourceHandle(
            projectAuthorityCoordinate: projectMeshCoordinate(from: initial),
            sourceID: asset.id,
            contentIdentity: asset.contentIdentity
        ),
        plan: try projectMeshUseCasePlan(vertexID: asset.source.vertexIDs[0], z: 6),
        snapshot: initial
    )

    var postCommitError: ProjectWorkspacePostCommitError?
    do {
        _ = try await workspace.commit(request)
    } catch let error as ProjectWorkspacePostCommitError {
        postCommitError = error
    }
    let state = try await controller.currentState()

    #expect(postCommitError?.stage == .viewProjection)
    #expect(postCommitError?.commit.state.transactionRevision == state.transactionRevision)
    #expect(state.transactionRevision.value == initial.transactionRevision.value + 1)
    #expect(state.canUndo)
    #expect(await workspace.view?.transactionRevision == initial.transactionRevision)
}

@Test(.timeLimit(.minutes(1)))
func projectMeshCommitWrapsDomainProjectionFailureAfterPublication() async throws {
    let document = try projectMeshUseCaseMeshOnlyDocument(named: "Domain Result Projection")
    let asset = try #require(document.authoredMeshAssets.values.first)
    let controller = try projectMeshUseCaseController(document: document)
    let buildCount = Mutex(0)
    let workspace = await ProjectWorkspace(
        project: controller,
        viewBuilder: ProjectMeshMismatchedViewBuilder(mismatchBuild: 2, count: buildCount)
    )
    let initial = try await workspace.evaluate()
    let request = ProjectMeshEditRequest(
        handle: ProjectMeshSourceHandle(
            projectAuthorityCoordinate: projectMeshCoordinate(from: initial),
            sourceID: asset.id,
            contentIdentity: asset.contentIdentity
        ),
        plan: try projectMeshUseCasePlan(vertexID: asset.source.vertexIDs[0], z: 7),
        snapshot: initial
    )

    var postCommitError: ProjectWorkspacePostCommitError?
    do {
        _ = try await workspace.commit(request)
    } catch let error as ProjectWorkspacePostCommitError {
        postCommitError = error
    }
    let state = try await controller.currentState()

    #expect(postCommitError?.stage == .domainResultProjection)
    if case .source(let commit)? = postCommitError?.commit {
        #expect(commit.state.transactionRevision == state.transactionRevision)
        #expect(commit.state.document.authoredMeshAssets[asset.id]?.contentIdentity != asset.contentIdentity)
    } else {
        Issue.record("The post-publication domain failure did not retain the exact source commit.")
    }
    #expect(state.transactionRevision.value == initial.transactionRevision.value + 1)
    #expect(state.canUndo)
}

@Test(.timeLimit(.minutes(1)))
func projectMeshCatalogGroupsSourcesPurposesAndReferenceBudget() async throws {
    var document = try projectMeshUseCaseMeshOnlyDocument(named: "Catalog Groups")
    let firstAsset = try #require(document.authoredMeshAssets.values.first)
    let firstNodeID = try #require(document.productMetadata.sceneNodes.first { entry in
        entry.value.object?.geometryRole == .mesh
    }?.key)
    let firstObject = try #require(document.productMetadata.sceneNodes[firstNodeID]?.object)
    let firstRepresentationID = try #require(
        firstObject.geometryRepresentations.selection?.modeling
    )

    let secondMesh = try projectMeshUseCaseTriangleMesh(identity: "mesh.catalog-a")
    let secondAsset = try AuthoredMeshAsset(source: secondMesh, provenance: .created)
    document.authoredMeshAssets[secondAsset.id] = secondAsset
    let secondRepresentationID: GeometryRepresentationID = "representation.second"
    let unselectedRepresentationID: GeometryRepresentationID = "representation.unselected"
    let secondNodeID = try document.productMetadata.appendSceneNodeToFirstRoot(
        name: "Second Mesh",
        reference: .authoredMesh(secondAsset.id),
        object: ObjectDescriptor(
            category: .body,
            geometryRole: .mesh,
            geometryRepresentations: GeometryRepresentationSet(
                representations: [
                    secondRepresentationID: GeometryRepresentation(
                        id: secondRepresentationID,
                        source: .authoredMesh(secondAsset.id)
                    ),
                    unselectedRepresentationID: GeometryRepresentation(
                        id: unselectedRepresentationID,
                        source: .authoredMesh(firstAsset.id)
                    ),
                ],
                selection: GeometryRepresentationSelection(
                    modeling: secondRepresentationID,
                    presentation: secondRepresentationID
                )
            )
        )
    )
    try document.validate()
    let controller = try projectMeshUseCaseController(document: document)
    let workspace = await ProjectWorkspace(project: controller)
    let view = try await workspace.evaluate()

    let catalog = try await workspace.catalog(
        from: view,
        limits: ProjectMeshReadLimits(maxReferenceUnits: 9)
    )
    #expect(catalog.sources.map(\.sourceID) == [firstAsset.id, secondAsset.id].sorted {
        $0.rawValue < $1.rawValue
    })
    let firstSource = try #require(catalog.source(for: firstAsset.id))
    let secondSource = try #require(catalog.source(for: secondAsset.id))
    let expectedFirstReferences = [
        ProjectMeshCatalogReference(
            sceneNodeID: firstNodeID,
            representationID: firstRepresentationID,
            selectedPurposes: [.modeling, .presentation]
        ),
        ProjectMeshCatalogReference(
            sceneNodeID: secondNodeID,
            representationID: unselectedRepresentationID,
            selectedPurposes: []
        ),
    ].sorted { lhs, rhs in
        if lhs.sceneNodeID != rhs.sceneNodeID {
            return lhs.sceneNodeID < rhs.sceneNodeID
        }
        return lhs.representationID.rawValue < rhs.representationID.rawValue
    }
    #expect(firstSource.references == expectedFirstReferences)
    #expect(secondSource.references == [
        ProjectMeshCatalogReference(
            sceneNodeID: secondNodeID,
            representationID: secondRepresentationID,
            selectedPurposes: [.modeling, .presentation]
        ),
    ])

    var boundaryError: ProjectMeshReadError?
    do {
        _ = try await workspace.catalog(
            from: view,
            limits: ProjectMeshReadLimits(maxReferenceUnits: 8)
        )
    } catch let error as ProjectMeshReadError {
        boundaryError = error
    }
    #expect(boundaryError?.code == .limitExceeded)

    let representationCount = document.productMetadata.sceneNodes.values.reduce(0) {
        $0 + ($1.object?.geometryRepresentations.representations.count ?? 0)
    }
    let sourceScanCount = document.authoredMeshAssets.values.reduce(0) { partial, asset in
        partial + [
            asset.source.vertexIDs.count,
            asset.source.edgeIDs.count,
            asset.source.faceIDs.count,
            asset.source.cornerIDs.count,
            asset.source.vertexPositions.count,
        ].reduce(0, +)
    }
    let cumulativeScanCount = document.productMetadata.sceneNodes.count
        + representationCount
        + document.authoredMeshAssets.count
        + sourceScanCount
    var cumulativeScanError: ProjectMeshReadError?
    do {
        _ = try await workspace.catalog(
            from: view,
            limits: ProjectMeshReadLimits(
                maxScannedRecords: cumulativeScanCount - 1,
                maxReferenceUnits: 9
            )
        )
    } catch let error as ProjectMeshReadError {
        cumulativeScanError = error
    }
    #expect(cumulativeScanError?.code == .limitExceeded)
}

@Test(.timeLimit(.minutes(1)))
func projectMeshCatalogScanBudgetRejectsBeforeMaterialization() async throws {
    let document = try projectMeshUseCaseMeshOnlyDocument(named: "Catalog Scan Boundary")
    let asset = try #require(document.authoredMeshAssets.values.first)
    let controller = try projectMeshUseCaseController(document: document)
    let workspace = await ProjectWorkspace(project: controller)
    let view = try await workspace.evaluate()
    let source = try #require(asset.source as MeshSource?)
    let representationCount = document.productMetadata.sceneNodes.values.reduce(0) {
        $0 + ($1.object?.geometryRepresentations.representations.count ?? 0)
    }
    let expectedScanCount = document.productMetadata.sceneNodes.count
        + representationCount
        + document.authoredMeshAssets.count
        + source.vertexIDs.count
        + source.edgeIDs.count
        + source.faceIDs.count
        + source.cornerIDs.count
        + source.vertexPositions.count

    let catalog = try await workspace.catalog(
        from: view,
        limits: ProjectMeshReadLimits(
            maxScannedRecords: expectedScanCount,
            maxReferenceUnits: 3
        )
    )
    #expect(catalog.sources.count == 1)

    var scanError: ProjectMeshReadError?
    do {
        _ = try await workspace.catalog(
            from: view,
            limits: ProjectMeshReadLimits(
                maxScannedRecords: expectedScanCount - 1,
                maxReferenceUnits: 3
            )
        )
    } catch let error as ProjectMeshReadError {
        scanError = error
    }
    #expect(scanError?.code == .limitExceeded)
}

@Test(.timeLimit(.minutes(1)))
func projectMeshNeighborhoodUsesNumericRawIDTieBreakAndBoundaries() async throws {
    let mesh = try projectMeshUseCaseNumericTieMesh(identity: "mesh.numeric-tie")
    var document = DesignDocument.empty(named: "Numeric Tie")
    let asset = try AuthoredMeshAsset(source: mesh, provenance: .created)
    document.authoredMeshAssets[asset.id] = asset
    let representationID: GeometryRepresentationID = "representation.numeric-tie"
    _ = try document.productMetadata.appendSceneNodeToFirstRoot(
        name: "Numeric Tie Mesh",
        reference: .authoredMesh(asset.id),
        object: ObjectDescriptor(
            category: .body,
            geometryRole: .mesh,
            geometryRepresentations: projectMeshUseCaseRepresentationSet(
                representationID: representationID,
                source: .authoredMesh(asset.id)
            )
        )
    )
    try document.validate()
    let controller = try projectMeshUseCaseController(document: document)
    let workspace = await ProjectWorkspace(project: controller)
    let view = try await workspace.evaluate()
    let handle = ProjectMeshSourceHandle(
        projectAuthorityCoordinate: projectMeshCoordinate(from: view),
        sourceID: asset.id,
        contentIdentity: asset.contentIdentity
    )
    let neighborhood = try await workspace.neighborhood(
        ProjectMeshNeighborhoodRequest(
            handle: handle,
            origin: .vertex(MeshVertexID(0)),
            depth: 2,
            limits: ProjectMeshReadLimits(maxReferenceUnits: 40)
        ),
        from: view
    )
    let distanceTwoVertices = neighborhood.records.compactMap { record -> UInt64? in
        guard record.distance == 2, case .vertex(let vertex) = record.element else {
            return nil
        }
        return vertex.id.rawValue
    }
    #expect(distanceTwoVertices == [2, 10])

    var nestedBoundaryError: ProjectMeshReadError?
    do {
        _ = try await workspace.page(
            ProjectMeshElementPageRequest(
                handle: handle,
                domain: .face,
                limits: ProjectMeshReadLimits(maxReferenceUnits: 3)
            ),
            from: view
        )
    } catch let error as ProjectMeshReadError {
        nestedBoundaryError = error
    }
    #expect(nestedBoundaryError?.code == .limitExceeded)
    let facePage = try await workspace.page(
        ProjectMeshElementPageRequest(
            handle: handle,
            domain: .face,
            limits: ProjectMeshReadLimits(maxReferenceUnits: 4)
        ),
        from: view
    )
    #expect(facePage.records.count == 1)
}

@Test(.timeLimit(.minutes(1)))
func projectMeshLateCornerAndLargeNeighborhoodHonorExactScanBudgets() async throws {
    let mesh = try projectMeshUseCaseManyTriangleMesh(
        identity: "mesh.bounded-index",
        faceCount: 64
    )
    var document = DesignDocument.empty(named: "Bounded Index")
    let asset = try AuthoredMeshAsset(source: mesh, provenance: .created)
    document.authoredMeshAssets[asset.id] = asset
    let representationID: GeometryRepresentationID = "representation.bounded-index"
    _ = try document.productMetadata.appendSceneNodeToFirstRoot(
        name: "Bounded Index Mesh",
        reference: .authoredMesh(asset.id),
        object: ObjectDescriptor(
            category: .body,
            geometryRole: .mesh,
            geometryRepresentations: projectMeshUseCaseRepresentationSet(
                representationID: representationID,
                source: .authoredMesh(asset.id)
            )
        )
    )
    try document.validate()
    let controller = try projectMeshUseCaseController(document: document)
    let workspace = await ProjectWorkspace(project: controller)
    let view = try await workspace.evaluate()
    let handle = ProjectMeshSourceHandle(
        projectAuthorityCoordinate: projectMeshCoordinate(from: view),
        sourceID: asset.id,
        contentIdentity: asset.contentIdentity
    )
    let lastCornerIndex = mesh.cornerIDs.count - 1
    let cursor = ProjectMeshElementCursor(
        sourceID: asset.id,
        contentIdentity: asset.contentIdentity,
        domain: .corner,
        nextIndex: lastCornerIndex
    )
    let lateCornerScanCount = 12
    let lateCorner = try await workspace.page(
        ProjectMeshElementPageRequest(
            handle: handle,
            domain: .corner,
            cursor: cursor,
            limits: ProjectMeshReadLimits(
                maxPageRecords: 1,
                maxScannedRecords: lateCornerScanCount,
                maxOutputRecords: 1,
                maxReferenceUnits: 6
            )
        ),
        from: view
    )
    #expect(lateCorner.records.first?.reference == .corner(mesh.cornerIDs[lastCornerIndex]))

    var lateCornerError: ProjectMeshReadError?
    do {
        _ = try await workspace.page(
            ProjectMeshElementPageRequest(
                handle: handle,
                domain: .corner,
                cursor: cursor,
                limits: ProjectMeshReadLimits(
                    maxPageRecords: 1,
                    maxScannedRecords: lateCornerScanCount - 1,
                    maxOutputRecords: 1,
                    maxReferenceUnits: 6
                )
            ),
            from: view
        )
    } catch let error as ProjectMeshReadError {
        lateCornerError = error
    }
    #expect(lateCornerError?.code == .limitExceeded)

    let sourceIndexScanCount = mesh.vertexIDs.count
        + (3 * mesh.edgeIDs.count)
        + mesh.faceIDs.count
        + (5 * mesh.cornerIDs.count)
    let depthOneOutputScanCount = 13
    let neighborhoodScanCount = sourceIndexScanCount + depthOneOutputScanCount
    let neighborhood = try await workspace.neighborhood(
        ProjectMeshNeighborhoodRequest(
            handle: handle,
            origin: .vertex(mesh.vertexIDs[0]),
            depth: 1,
            limits: ProjectMeshReadLimits(
                maxNeighborhoodDepth: 1,
                maxScannedRecords: neighborhoodScanCount,
                maxOutputRecords: 4,
                maxReferenceUnits: depthOneOutputScanCount
            )
        ),
        from: view
    )
    #expect(neighborhood.records.count == 4)

    var neighborhoodScanError: ProjectMeshReadError?
    do {
        _ = try await workspace.neighborhood(
            ProjectMeshNeighborhoodRequest(
                handle: handle,
                origin: .vertex(mesh.vertexIDs[0]),
                depth: 1,
                limits: ProjectMeshReadLimits(
                    maxNeighborhoodDepth: 1,
                    maxScannedRecords: neighborhoodScanCount - 1,
                    maxOutputRecords: 4,
                    maxReferenceUnits: depthOneOutputScanCount
                )
            ),
            from: view
        )
    } catch let error as ProjectMeshReadError {
        neighborhoodScanError = error
    }
    #expect(neighborhoodScanError?.code == .limitExceeded)
}

private func projectMeshUseCaseController(document: DesignDocument) throws -> ProjectController {
    try ProjectController(
        document: document,
        evaluatorPreparer: DefaultDesignDocumentProjectEvaluatorFactory(),
        projector: DesignDocumentProjectBridge()
    )
}

private func projectMeshUseCaseMeshOnlyDocument(named name: String) throws -> DesignDocument {
    var document = DesignDocument.empty(named: name)
    let mesh = try projectMeshUseCaseTriangleMesh(identity: "mesh.usecase-only")
    let asset = try AuthoredMeshAsset(source: mesh, provenance: .created)
    let representationID: GeometryRepresentationID = "representation.usecase-only"
    document.authoredMeshAssets[asset.id] = asset
    _ = try document.productMetadata.appendSceneNodeToFirstRoot(
        name: "Mesh",
        reference: .authoredMesh(asset.id),
        object: ObjectDescriptor(
            category: .body,
            geometryRole: .mesh,
            geometryRepresentations: projectMeshUseCaseRepresentationSet(
                representationID: representationID,
                source: .authoredMesh(asset.id)
            )
        )
    )
    try document.validate()
    return document
}

private func projectMeshUseCaseCADAndMeshDocument(named name: String) throws -> DesignDocument {
    var document = DesignDocument.empty(named: name)
    let featureID = try document.createExtrudedRectangle(
        name: "Body",
        plane: .xy,
        width: .length(1, .meter),
        height: .length(1, .meter),
        depth: .length(1, .meter),
        direction: .normal
    )
    let bodyNodeID = try #require(document.productMetadata.sceneNodes.first { entry in
        entry.value.reference == .body(featureID)
    }?.key)
    var object = try #require(document.productMetadata.sceneNodes[bodyNodeID]?.object)
    let cadRepresentationID = try #require(object.geometryRepresentations.selection?.modeling)
    let mesh = try projectMeshUseCaseTriangleMesh(identity: "mesh.usecase-mixed")
    let asset = try AuthoredMeshAsset(source: mesh, provenance: .created)
    let meshRepresentationID: GeometryRepresentationID = "representation.usecase-mixed"
    document.authoredMeshAssets[asset.id] = asset
    object.geometryRepresentations.representations[meshRepresentationID] = GeometryRepresentation(
        id: meshRepresentationID,
        source: .authoredMesh(asset.id)
    )
    object.geometryRepresentations.selection = GeometryRepresentationSelection(
        modeling: cadRepresentationID,
        presentation: meshRepresentationID
    )
    document.productMetadata.sceneNodes[bodyNodeID]?.object = object
    try document.validate()
    return document
}

private func projectMeshUseCaseRepresentationSet(
    representationID: GeometryRepresentationID,
    source: GeometrySourceReference
) -> GeometryRepresentationSet {
    GeometryRepresentationSet(
        representations: [
            representationID: GeometryRepresentation(id: representationID, source: source),
        ],
        selection: GeometryRepresentationSelection(
            modeling: representationID,
            presentation: representationID
        )
    )
}

private func projectMeshUseCaseTriangleMesh(identity: GeometrySourceID) throws -> MeshSource {
    var builder = MeshSourceBuilder(identity: identity)
    let first = try builder.addVertex(GeometryPoint3D(x: 0, y: 0, z: 0))
    let second = try builder.addVertex(GeometryPoint3D(x: 1, y: 0, z: 0))
    let third = try builder.addVertex(GeometryPoint3D(x: 0, y: 1, z: 0))
    _ = try builder.addFace(vertexIDs: [first, second, third])
    return try builder.build()
}

private func projectMeshUseCaseNumericTieMesh(identity: GeometrySourceID) throws -> MeshSource {
    try MeshSource(
        identity: identity,
        allocationState: MeshElementIDAllocationState(
            nextVertexID: MeshVertexID(11),
            nextEdgeID: MeshEdgeID(3),
            nextFaceID: MeshFaceID(1),
            nextCornerID: MeshCornerID(3)
        ),
        vertexIDs: GeometryBuffer([
            MeshVertexID(0),
            MeshVertexID(2),
            MeshVertexID(10),
        ]),
        vertexPositions: GeometryBuffer([
            GeometryPoint3D(x: 0, y: 0, z: 0),
            GeometryPoint3D(x: 1, y: 0, z: 0),
            GeometryPoint3D(x: 0, y: 1, z: 0),
        ]),
        edgeIDs: GeometryBuffer([
            MeshEdgeID(0),
            MeshEdgeID(1),
            MeshEdgeID(2),
        ]),
        edgeEndpoints: GeometryBuffer([
            MeshEdgeEndpoints(start: MeshVertexID(0), end: MeshVertexID(2)),
            MeshEdgeEndpoints(start: MeshVertexID(2), end: MeshVertexID(10)),
            MeshEdgeEndpoints(start: MeshVertexID(10), end: MeshVertexID(0)),
        ]),
        faceIDs: GeometryBuffer([MeshFaceID(0)]),
        faceCornerRanges: GeometryBuffer([MeshIndexRange(start: 0, count: 3)]),
        cornerIDs: GeometryBuffer([
            MeshCornerID(0),
            MeshCornerID(1),
            MeshCornerID(2),
        ]),
        cornerVertexIDs: GeometryBuffer([
            MeshVertexID(0),
            MeshVertexID(2),
            MeshVertexID(10),
        ]),
        cornerEdgeIDs: GeometryBuffer([
            MeshEdgeID(0),
            MeshEdgeID(1),
            MeshEdgeID(2),
        ])
    )
}

private func projectMeshUseCaseManyTriangleMesh(
    identity: GeometrySourceID,
    faceCount: Int
) throws -> MeshSource {
    var builder = MeshSourceBuilder(identity: identity)
    for faceIndex in 0..<faceCount {
        let x = Double(faceIndex * 2)
        let first = try builder.addVertex(GeometryPoint3D(x: x, y: 0, z: 0))
        let second = try builder.addVertex(GeometryPoint3D(x: x + 1, y: 0, z: 0))
        let third = try builder.addVertex(GeometryPoint3D(x: x, y: 1, z: 0))
        _ = try builder.addFace(vertexIDs: [first, second, third])
    }
    return try builder.build()
}

private func projectMeshUseCasePlan(vertexID: MeshVertexID, z: Double) throws -> MeshEditPlan {
    try MeshEditPlan(
        steps: [
            MeshEditStep(
                id: MeshEditStepID("set-vertex-position"),
                operation: .primitive(
                    .setVertexPositions([
                        try MeshVertexPositionEdit(
                            vertexID: vertexID,
                            position: GeometryPoint3D(x: 0, y: 0, z: z)
                        ),
                    ])
                )
            ),
        ]
    )
}

private func projectMeshCoordinate(from view: ProjectViewSnapshot) -> ProjectAuthorityCoordinate {
    ProjectAuthorityCoordinate(
        projectID: view.projectID,
        transactionRevision: view.transactionRevision,
        publicationSequence: view.publicationSequence
    )
}

private func projectMeshAlternateContentIdentity() throws -> ContentIdentity {
    try ContentIdentity(
        domain: "rupa.geometry-source.v1",
        fingerprint: try ContentFingerprint.sha256(
            algorithm: "sha256-mesh-use-case",
            data: Data("different-content".utf8)
        )
    )
}

private final class ProjectMeshFailingViewBuilder: ProjectViewSnapshotBuilding, Sendable {
    let failingBuild: Int
    let count: Mutex<Int>

    init(failingBuild: Int, count: consuming Mutex<Int>) {
        self.failingBuild = failingBuild
        self.count = count
    }

    func build(from state: ProjectStateSnapshot) throws -> ProjectViewSnapshot {
        let buildNumber = count.withLock {
            $0 += 1
            return $0
        }
        guard buildNumber != failingBuild else {
            throw ProjectViewSnapshotError(
                code: .sourceMismatch,
                message: "The fixture rejected the post-commit view projection."
            )
        }
        return try ProjectViewSnapshotBuilder().build(from: state)
    }
}

private final class ProjectMeshMismatchedViewBuilder: ProjectViewSnapshotBuilding, Sendable {
    let mismatchBuild: Int
    let count: Mutex<Int>
    let retainedView = Mutex<ProjectViewSnapshot?>(nil)

    init(mismatchBuild: Int, count: consuming Mutex<Int>) {
        self.mismatchBuild = mismatchBuild
        self.count = count
    }

    func build(from state: ProjectStateSnapshot) throws -> ProjectViewSnapshot {
        let candidate = try ProjectViewSnapshotBuilder().build(from: state)
        let buildNumber = count.withLock {
            $0 += 1
            return $0
        }
        return retainedView.withLock { retained in
            if buildNumber == mismatchBuild, let retained {
                return retained
            }
            if retained == nil {
                retained = candidate
            }
            return candidate
        }
    }
}

private extension ProjectMeshElementDomain {
    var sortOrderForTesting: Int {
        switch self {
        case .vertex:
            0
        case .edge:
            1
        case .face:
            2
        case .corner:
            3
        }
    }
}
