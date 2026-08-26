import CoreGraphics
import RupaCore
import RupaCoreTypes
import RupaViewportScene
import SwiftCAD
import Testing
@testable import RupaRendering

@MainActor
@Test(.timeLimit(.minutes(1)))
func viewportOccurrenceSelectionKeepsExactSceneNodeForSharedCADFeature() throws {
    let fixture = try sharedCADFeatureOccurrenceFixture()
    let scene = ViewportSceneBuilder().build(
        document: fixture.document,
        ruler: .standard(for: .millimeter)
    )
    let selection = SelectionModel(
        selectedTargets: [SelectionTarget(sceneNodeID: fixture.visibleSceneNodeID)]
    )
    let index = ViewportObjectSelectionIndex(
        document: fixture.document,
        selection: selection
    )
    let selectedItems = index.selectedBodySourceItems(in: scene)
    let selectedItem = try #require(selectedItems.first)
    let exactTarget = try #require(index.exactTarget(for: selectedItem))
    let moveTarget = ViewportBodyMoveDragTarget(
        target: exactTarget,
        deltaX: 0.01,
        deltaY: 0.02
    )

    #expect(scene.items.contains { $0.sceneNodeID == fixture.hiddenSceneNodeID } == false)
    #expect(scene.items.contains { $0.sceneNodeID == fixture.visibleSceneNodeID })
    #expect(selectedItems.map(\.sceneNodeID) == [fixture.visibleSceneNodeID])
    #expect(index.sceneNodeIDs == [fixture.visibleSceneNodeID])
    #expect(moveTarget.target.sceneNodeID == fixture.visibleSceneNodeID)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func viewportSceneBuilderCreatesDistinctRootOccurrencesForSharedCADFeature() throws {
    var fixture = try sharedCADFeatureOccurrenceFixture()
    fixture.document.productMetadata.sceneNodes[fixture.hiddenSceneNodeID]?.isVisible = true

    let scene = ViewportSceneBuilder().build(
        document: fixture.document,
        ruler: .standard(for: .millimeter)
    )
    let sharedItems = scene.items.filter { $0.featureID == fixture.featureID }

    #expect(Set(sharedItems.compactMap(\.sceneNodeID)) == [
        fixture.hiddenSceneNodeID,
        fixture.visibleSceneNodeID,
    ])
    #expect(Set(sharedItems.map(\.id)).count == 2)
    #expect(sharedItems.first { $0.sceneNodeID == fixture.visibleSceneNodeID }?
        .modelTransform.matrix.values[12] == 0.25)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func viewportOccurrenceSelectionUsesPrimarySceneNodeWhenSharedSourceIsSelectedTwice() throws {
    var fixture = try sharedCADFeatureOccurrenceFixture()
    fixture.document.productMetadata.sceneNodes[fixture.hiddenSceneNodeID]?.isVisible = true
    let scene = ViewportSceneBuilder().build(
        document: fixture.document,
        ruler: .standard(for: .millimeter)
    )
    let firstIndex = ViewportObjectSelectionIndex(
        document: fixture.document,
        selection: SelectionModel(selectedTargets: [
            SelectionTarget(sceneNodeID: fixture.hiddenSceneNodeID),
            SelectionTarget(sceneNodeID: fixture.visibleSceneNodeID),
        ])
    )
    let reversedIndex = ViewportObjectSelectionIndex(
        document: fixture.document,
        selection: SelectionModel(selectedTargets: [
            SelectionTarget(sceneNodeID: fixture.visibleSceneNodeID),
            SelectionTarget(sceneNodeID: fixture.hiddenSceneNodeID),
        ])
    )

    #expect(firstIndex.selectedBodySourceItems(in: scene).map(\.sceneNodeID) == [
        fixture.visibleSceneNodeID,
    ])
    #expect(reversedIndex.selectedBodySourceItems(in: scene).map(\.sceneNodeID) == [
        fixture.hiddenSceneNodeID,
    ])
}

@Test(.timeLimit(.minutes(1)))
func meshSourcePresentationInteractionStateUsesExactSelectedHoverAndPreviewOccurrences() {
    let selectedSceneNodeID = SceneNodeID()
    let hoveredSceneNodeID = SceneNodeID()
    let previewSceneNodeID = SceneNodeID()
    let selectedOccurrenceID = SceneOccurrenceID(rawValue: "occurrence.selected")
    let hoveredOccurrenceID = SceneOccurrenceID(rawValue: "occurrence.hovered")
    let previewOccurrenceID = SceneOccurrenceID(rawValue: "occurrence.preview")
    let unmappedOccurrenceID = SceneOccurrenceID(rawValue: "occurrence.unmapped")
    let resolver = MeshSourcePresentationInteractionStateResolver(
        sceneNodeIDByOccurrenceID: [
            selectedOccurrenceID: selectedSceneNodeID,
            hoveredOccurrenceID: hoveredSceneNodeID,
            previewOccurrenceID: previewSceneNodeID,
        ],
        selectedSceneNodeIDs: [selectedSceneNodeID],
        previewSceneNodeIDs: [previewSceneNodeID],
        hoveredSceneNodeID: hoveredSceneNodeID
    )

    #expect(resolver.state(for: selectedOccurrenceID) == .selected)
    #expect(resolver.state(for: hoveredOccurrenceID) == .hovered)
    #expect(resolver.state(for: previewOccurrenceID) == .hovered)
    #expect(resolver.state(for: unmappedOccurrenceID) == .normal)
}

@Test(.timeLimit(.minutes(1)))
func exactCADSelectionContextIncludesSubshapeTargetsWithoutObjectIndexing() {
    let sceneNodeID = SceneNodeID()
    let selection = SelectionModel(
        selectedTargets: [
            SelectionTarget(
                sceneNodeID: sceneNodeID,
                component: .face(.bodyFaceTop)
            ),
        ]
    )
    let resolver = MeshSourcePresentationExactCADSelectionResolver(
        availableSceneNodeIDs: [sceneNodeID]
    )

    #expect(resolver.hasExactContext(for: selection))
    #expect(!resolver.hasExactContext(for: .empty))
}

@MainActor
private func sharedCADFeatureOccurrenceFixture() throws -> (
    document: DesignDocument,
    featureID: FeatureID,
    hiddenSceneNodeID: SceneNodeID,
    visibleSceneNodeID: SceneNodeID
) {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    var document = session.document
    let hiddenEntry = try #require(document.productMetadata.sceneNodes.first { _, node in
        node.reference?.kind == .body
    })
    let featureID = try #require(hiddenEntry.value.reference?.featureID)
    let visibleSceneNodeID = SceneNodeID()
    document.productMetadata.sceneNodes[hiddenEntry.key]?.isVisible = false
    document.productMetadata.sceneNodes[visibleSceneNodeID] = SceneNode(
        id: visibleSceneNodeID,
        name: "Visible shared CAD occurrence",
        reference: .body(featureID),
        localTransform: try occurrenceTranslationTransform(x: 0.25)
    )
    document.productMetadata.rootSceneNodeIDs.append(visibleSceneNodeID)
    return (
        document: document,
        featureID: featureID,
        hiddenSceneNodeID: hiddenEntry.key,
        visibleSceneNodeID: visibleSceneNodeID
    )
}

private func occurrenceTranslationTransform(x: Double) throws -> Transform3D {
    Transform3D(matrix: try Matrix4x4(values: [
        1.0, 0.0, 0.0, 0.0,
        0.0, 1.0, 0.0, 0.0,
        0.0, 0.0, 1.0, 0.0,
        x, 0.0, 0.0, 1.0,
    ]))
}
