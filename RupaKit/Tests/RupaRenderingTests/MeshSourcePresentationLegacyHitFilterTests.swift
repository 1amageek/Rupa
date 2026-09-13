import RupaCore
import RupaCoreTypes
import RupaViewportScene
import Testing
@testable import RupaRendering

@Test(.timeLimit(.minutes(1)))
func presentationLegacyHitFilterUsesOccurrencesForObjectsAndExactCADForSubshapes() {
    let sceneNodeID = SceneNodeID()
    let occurrenceID = SceneOccurrenceID(rawValue: "occurrence.visible")
    let bodyHit = ViewportHit(
        featureID: FeatureID(),
        sceneNodeID: sceneNodeID,
        kind: .body,
        selectionComponent: .face(SelectionComponentID(rawValue: "face.visible"))
    )
    let filter = MeshSourcePresentationLegacyHitFilter()
    let navigation = [occurrenceID: sceneNodeID]

    #expect(filter.selectionHits(
        [bodyHit],
        visiblePresentationOccurrenceIDs: [occurrenceID],
        navigation: navigation,
        exactCADSceneNodeIDs: [sceneNodeID],
        selectionHitPolicy: .object
    ).isEmpty)
    #expect(filter.selectionHits(
        [bodyHit],
        visiblePresentationOccurrenceIDs: [occurrenceID],
        navigation: navigation,
        exactCADSceneNodeIDs: [sceneNodeID],
        selectionHitPolicy: .face
    ) == [bodyHit])
    #expect(filter.selectionHits(
        [bodyHit],
        visiblePresentationOccurrenceIDs: [],
        navigation: navigation,
        exactCADSceneNodeIDs: [sceneNodeID],
        selectionHitPolicy: .face
    ).isEmpty)
}
