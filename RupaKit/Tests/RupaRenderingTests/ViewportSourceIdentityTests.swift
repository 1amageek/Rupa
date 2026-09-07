import RupaCore
import RupaCoreTypes
import RupaViewportScene
import Testing
@testable import RupaRendering

private func sourceIdentityScene(
    projectID: ProjectID,
    revision: UInt64 = 1,
    snapshotProjectID: ProjectID? = nil
) -> UniversalViewportScene {
    let snapshotID = EvaluationSnapshotID(
        projectID: snapshotProjectID ?? projectID,
        purpose: .presentation,
        sourceRevision: DocumentTransactionRevision(revision)
    )
    return UniversalViewportScene(snapshotID: snapshotID, projectID: projectID, items: [])
}

@MainActor
private func sourceIdentityViewport(
    document: DesignDocument,
    identity: ViewportSourceIdentity,
    scene: UniversalViewportScene?
) -> Viewport {
    Viewport(
        document: document,
        sourceIdentity: identity,
        presentationScene: scene,
        workspaceRenderState: .init(
            revision: WorkspaceRevision(),
            ruler: .standard(for: .millimeter)
        ),
        objectSelectionIndex: ViewportObjectSelectionIndex(
            document: document,
            selection: .empty
        ),
        selectedPresentationHasExactCADContext: true
    )
}

@MainActor
@Test
func viewportSourceValidationAcceptsMatchingDocumentAndScene() {
    let document = DesignDocument.empty()
    let scene = sourceIdentityScene(projectID: document.projectID)
    let viewport = sourceIdentityViewport(
        document: document,
        identity: .document(id: document.id, generation: DocumentGeneration(1)),
        scene: scene
    )
    #expect(viewport.sourceValidationFailure == nil)
}

@MainActor
@Test
func viewportSourceValidationRejectsWrongDocumentIdentity() {
    let document = DesignDocument.empty()
    let otherDocument = DesignDocument.empty()
    let viewport = sourceIdentityViewport(
        document: document,
        identity: .document(id: otherDocument.id, generation: DocumentGeneration(1)),
        scene: nil
    )
    #expect(viewport.sourceValidationFailure?.code == .sourceAuthorityMismatch)
}

@MainActor
@Test
func viewportSourceValidationRejectsDocumentWithInconsistentSceneSnapshot() {
    let document = DesignDocument.empty()
    let inconsistentScene = sourceIdentityScene(
        projectID: document.projectID,
        snapshotProjectID: DesignDocument.empty().projectID
    )
    let viewport = sourceIdentityViewport(
        document: document,
        identity: .document(id: document.id, generation: DocumentGeneration(1)),
        scene: inconsistentScene
    )
    #expect(viewport.sourceValidationFailure?.code == .sourceAuthorityMismatch)
}

@MainActor
@Test
func viewportSourceValidationAcceptsExactPresentationSnapshot() {
    let document = DesignDocument.empty()
    let scene = sourceIdentityScene(projectID: document.projectID)
    let viewport = sourceIdentityViewport(
        document: document,
        identity: .presentation(scene.snapshotID),
        scene: scene
    )
    #expect(viewport.sourceValidationFailure == nil)
}

@MainActor
@Test
func viewportSourceValidationRejectsInvalidPresentationCases() {
    let document = DesignDocument.empty()
    let expectedScene = sourceIdentityScene(projectID: document.projectID)
    let identity = ViewportSourceIdentity.presentation(expectedScene.snapshotID)
    let otherDocument = DesignDocument.empty()
    let invalidScenes: [UniversalViewportScene?] = [
        nil,
        sourceIdentityScene(projectID: document.projectID, revision: 2),
        sourceIdentityScene(projectID: otherDocument.projectID),
        sourceIdentityScene(
            projectID: document.projectID,
            snapshotProjectID: otherDocument.projectID
        )
    ]

    for scene in invalidScenes {
        let viewport = sourceIdentityViewport(
            document: document,
            identity: identity,
            scene: scene
        )
        #expect(viewport.sourceValidationFailure?.code == .sourceAuthorityMismatch)
    }
}
