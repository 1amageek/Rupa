import CoreGraphics
import RupaCore
import RupaCoreTypes
import RupaViewportScene
import SwiftCAD
import Testing
@testable import RupaRendering

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
