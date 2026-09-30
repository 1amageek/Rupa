import RupaCore
import RupaViewportScene
import SwiftCAD
import Testing
@testable import RupaRendering

@MainActor
@Test func spatialOverlayRevisionDoesNotReuseEarlierInteractionIdentity() throws {
    let owner = ViewportSpatialOverlayRevision()
    let first = ViewportSpatialOverlayChangeKey()
    #expect(try owner.revision(for: first) == 1)
    #expect(try owner.revision(for: first) == 1)
    var selected = first
    selected.selection = SelectionModel(selectedTargets: [.init(sceneNodeID: SceneNodeID())])
    #expect(try owner.revision(for: selected) == 2)
    #expect(try owner.revision(for: first) == 3)
    var policy = first
    policy.availableRoutes = 1
    #expect(try owner.revision(for: policy) == 4)
    policy.measurementToolActive = true
    #expect(try owner.revision(for: policy) == 5)
    policy.nativeAxisValue = 0.01
    #expect(try owner.revision(for: policy) == 6)
    policy.nativeAxisValue = .nan
    #expect(throws: MeshSourcePresentationRenderError.self) { try owner.revision(for: policy) }
    policy.nativeAxisValue = 0.01
    #expect(try owner.revision(for: policy) == 6)
}

@MainActor
@Test func spatialOverlayRevisionRefusesOverflowAndInvalidDimensions() throws {
    let owner = ViewportSpatialOverlayRevision(initialValue: UInt64.max - 1)
    var key = ViewportSpatialOverlayChangeKey()
    #expect(try owner.revision(for: key) == UInt64.max)
    #expect(try owner.revision(for: key) == UInt64.max)
    key.measurementToolActive = true
    do {
        _ = try owner.revision(for: key)
        Issue.record("Overlay revision wrapped around.")
    } catch { #expect(error.code == .sizeOverflow) }
    let fresh = ViewportSpatialOverlayRevision()
    key.slotWidthMeters = .nan
    #expect(throws: MeshSourcePresentationRenderError.self) { try fresh.revision(for: key) }
    key.slotWidthMeters = 1
    #expect(try fresh.revision(for: key) == 1)
}

@MainActor
@Test func productionOverlayKeyExcludesCameraChromeAndDisplayMode() throws {
    let document = DesignDocument.empty()
    let workspace = ViewportWorkspaceRenderState(revision: WorkspaceRevision(), ruler: .standard(for: .millimeter))
    let objects = ViewportObjectSelectionIndex(document: document, selection: .empty)
    let first = Viewport(
        document: document, sourceIdentity: .document(id: document.id, generation: DocumentGeneration(1)),
        workspaceRenderState: workspace, objectSelectionIndex: objects,
        selectedPresentationHasExactCADContext: true
    )
    let changedChrome = Viewport(
        document: document, sourceIdentity: .document(id: document.id, generation: DocumentGeneration(1)),
        displayMode: .wireframe, workspaceRenderState: workspace, objectSelectionIndex: objects,
        bottomChromeReservedHeight: 100, gridVisualSpacingMode: .adaptive,
        cameraResetSignal: 42, selectedPresentationHasExactCADContext: true
    )
    let enabledRoute = Viewport(
        document: document, sourceIdentity: .document(id: document.id, generation: DocumentGeneration(1)),
        workspaceRenderState: workspace, objectSelectionIndex: objects,
        selectedPresentationHasExactCADContext: true, onRegionOffsetDrag: { _ in }
    )
    #expect(try first.makeSpatialOverlayChangeKey() == changedChrome.makeSpatialOverlayChangeKey())
    #expect(try first.makeSpatialOverlayChangeKey() != enabledRoute.makeSpatialOverlayChangeKey())
}

@MainActor
@Test func spatialOverlayBaseRevisionAdvancesOnlyBeyondHover() throws {
    let owner = ViewportSpatialOverlayRevision()
    let selected = SelectionTarget(sceneNodeID: SceneNodeID())
    var key = ViewportSpatialOverlayChangeKey()
    key.selection = SelectionModel(selectedTargets: [selected])
    #expect(try owner.revisions(for: key) == .init(overlay: 1, base: 1))
    var hovered = key
    hovered.selection = SelectionModel(selectedTargets: [selected],
                                       hoveredTarget: .init(sceneNodeID: SceneNodeID()))
    hovered.edgeTreatmentHoverTarget = selected
    #expect(try owner.revisions(for: hovered) == .init(overlay: 2, base: 1))
    // Leaving hover is a hover change too.
    #expect(try owner.revisions(for: key) == .init(overlay: 3, base: 1))
    var reselected = hovered
    reselected.selection = SelectionModel(selectedTargets: [selected, .init(sceneNodeID: SceneNodeID())],
                                          hoveredTarget: hovered.selection.hoveredTarget)
    #expect(try owner.revisions(for: reselected) == .init(overlay: 4, base: 2))
    var measuring = reselected
    measuring.measurementToolActive = true
    #expect(try owner.revisions(for: measuring) == .init(overlay: 5, base: 3))
    #expect(try owner.revisions(for: measuring) == .init(overlay: 5, base: 3))
}
