import RupaCore
import RupaCoreTypes
import RupaViewportScene
import Testing
@testable import RupaRendering

@Test(.timeLimit(.minutes(1)))
func presentationLegacyHitFilterRejectsHiddenOrMismatchedCADBodies() {
    let exactSceneNodeID = SceneNodeID()
    let hiddenSceneNodeID = SceneNodeID()
    let occurrenceID = SceneOccurrenceID(rawValue: "occurrence.exact")
    let exactHit = ViewportHit(
        featureID: FeatureID(),
        sceneNodeID: exactSceneNodeID,
        kind: .body
    )
    let hiddenHit = ViewportHit(
        featureID: FeatureID(),
        sceneNodeID: hiddenSceneNodeID,
        kind: .body
    )
    let sketchHit = ViewportHit(featureID: FeatureID(), kind: .sketch)
    let filter = MeshSourcePresentationLegacyHitFilter()
    let navigation = [occurrenceID: exactSceneNodeID]

    #expect(filter.hit(
        exactHit,
        presentationOccurrenceID: occurrenceID,
        navigation: navigation,
        exactCADSceneNodeIDs: [exactSceneNodeID]
    ) == exactHit)
    #expect(filter.hit(
        hiddenHit,
        presentationOccurrenceID: occurrenceID,
        navigation: navigation,
        exactCADSceneNodeIDs: [exactSceneNodeID]
    ) == nil)
    #expect(filter.hit(
        exactHit,
        presentationOccurrenceID: nil,
        navigation: navigation,
        exactCADSceneNodeIDs: [exactSceneNodeID]
    ) == nil)
    #expect(filter.hit(
        sketchHit,
        presentationOccurrenceID: occurrenceID,
        navigation: navigation,
        exactCADSceneNodeIDs: []
    ) == sketchHit)
}

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
