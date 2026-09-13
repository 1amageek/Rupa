import CoreGraphics
import RupaCore
import RupaCoreTypes
import RupaGeometry
import RupaProjectModel
import RupaViewportScene
import Testing
@testable import RupaRendering

// MARK: - Drawn frame provenance

private let drawnOccurrenceID = SceneOccurrenceID(rawValue: "occurrence.drawn")
private let undrawnOccurrenceID = SceneOccurrenceID(rawValue: "occurrence.other")
private let drawnSceneNodeID = SceneNodeID()
private let drawnFeatureID = FeatureID()

/// One triangle of the occurrence the frame drew at the pointer.
///
/// The occurrence family reads nothing from this triangle but the occurrence it
/// belongs to. Its source reference is an authored mesh on purpose: an
/// occurrence is what the frame drew, whatever geometry it drew, so a body with
/// no prepared CAD topology must be admitted here exactly as a CAD body is.
private func drawnTriangle(
    occurrenceID: SceneOccurrenceID = drawnOccurrenceID
) -> MeshSourcePresentationTriangle {
    MeshSourcePresentationTriangle(
        occurrenceID: occurrenceID,
        definitionID: ObjectDefinitionID(rawValue: "definition.drawn"),
        representationID: GeometryRepresentationID(rawValue: "representation.drawn"),
        sourceReference: .authoredMesh(GeometrySourceID(rawValue: "mesh.drawn")),
        faceID: MeshFaceID(3),
        firstVertexID: MeshVertexID(0),
        secondVertexID: MeshVertexID(1),
        thirdVertexID: MeshVertexID(2),
        firstPosition: GeometryPoint3D(x: 0, y: 0, z: 0),
        secondPosition: GeometryPoint3D(x: 1, y: 0, z: 0),
        thirdPosition: GeometryPoint3D(x: 1, y: 0, z: 1)
    )
}

/// The scene item carrying the drawn occurrence.
///
/// `modelBounds` is deliberately empty. The replaced rule projected a
/// candidate's bounds and admitted the occurrence wherever that box covered the
/// pointer, so a resolver that still consulted bounds would refuse every case
/// below; admitting them proves the drawn triangle is the whole rule.
private func drawnSceneItems() -> [ViewportSceneItem] {
    [
        ViewportSceneItem(
            id: "body.drawn",
            featureID: drawnFeatureID,
            sceneNodeID: drawnSceneNodeID,
            modelBounds: .zero,
            kind: .body(component: ViewportBodyComponent(
                sizeXMeters: 1,
                sizeYMeters: 1,
                sizeZMeters: 1,
                yMinMeters: 0,
                yMaxMeters: 1
            ))
        )
    ]
}

private let drawnNavigation: [SceneOccurrenceID: SceneNodeID] = [
    drawnOccurrenceID: drawnSceneNodeID
]

// MARK: - Occurrence admission

@Test
func nativeOverlayResolverNamesTheOccurrenceTheFrameDrew() throws {
    let answer = try #require(ViewportNativeOverlayHitResolver.occurrence(
        drawnBy: drawnTriangle(),
        navigation: drawnNavigation,
        items: drawnSceneItems(),
        selectionHitPolicy: .object
    ))
    #expect(answer.hit.sceneNodeID == drawnSceneNodeID)
    #expect(answer.hit.featureID == drawnFeatureID)
    #expect(answer.hit.kind == .body)
    #expect(answer.hit.pickingBackend == .native)
    #expect(answer.hit.selectionComponent == .object)
    #expect(answer.candidate.rank == .object)
    #expect(answer.candidate.metric == 0)
}

@Test
func nativeOverlayResolverRefusesAScopeThatAdmitsNoObject() {
    for policy in [ViewportSelectionHitPolicy.face, .edge, .vertex, .region, .sketchEntity] {
        #expect(ViewportNativeOverlayHitResolver.occurrence(
            drawnBy: drawnTriangle(),
            navigation: drawnNavigation,
            items: drawnSceneItems(),
            selectionHitPolicy: policy
        ) == nil, "\(policy) admits no object hit")
    }
}

@Test
func nativeOverlayResolverAdmitsTheOccurrenceUnderTheCombinedScope() throws {
    let answer = try #require(ViewportNativeOverlayHitResolver.occurrence(
        drawnBy: drawnTriangle(),
        navigation: drawnNavigation,
        items: drawnSceneItems(),
        selectionHitPolicy: .all
    ))
    #expect(answer.hit.sceneNodeID == drawnSceneNodeID)
}

/// A drawn occurrence the scene does not navigate is a miss, never a selection
/// named after the renderer's own identifier.
@Test
func nativeOverlayResolverRefusesAnOccurrenceSceneNavigationDoesNotName() {
    #expect(ViewportNativeOverlayHitResolver.occurrence(
        drawnBy: drawnTriangle(occurrenceID: undrawnOccurrenceID),
        navigation: drawnNavigation,
        items: drawnSceneItems(),
        selectionHitPolicy: .object
    ) == nil)
}

@Test
func nativeOverlayResolverRefusesAnOccurrenceNoSceneItemCarries() {
    #expect(ViewportNativeOverlayHitResolver.occurrence(
        drawnBy: drawnTriangle(),
        navigation: drawnNavigation,
        items: [],
        selectionHitPolicy: .object
    ) == nil)
}

// MARK: - Rank order

/// The occurrence is the weakest candidate, so a pointer that also named a
/// sub-shape of the same occurrence resolves to the sub-shape.
@Test
func nativeOverlayOccurrenceLosesToEverySubshapeRank() throws {
    let subshapeID = SelectionComponentID.generatedTopology(
        SubshapeID(featureID: drawnFeatureID, role: "face", ordinal: 1)
    )
    let occurrence = try #require(ViewportNativeOverlayHitResolver.occurrence(
        drawnBy: drawnTriangle(),
        navigation: drawnNavigation,
        items: drawnSceneItems(),
        selectionHitPolicy: .all
    )).candidate
    let subshapes: [ViewportNativeHitCandidate] = [
        // A face metric is a camera depth and a point metric is a screen
        // distance, so each is given a value far worse than the occurrence's
        // zero: rank has to decide these, not metric.
        ViewportNativeHitCandidate(component: .face(subshapeID), rank: .face, metric: 900),
        ViewportNativeHitCandidate(component: .edge(subshapeID), rank: .edge, metric: 900),
        ViewportNativeHitCandidate(component: .vertex(subshapeID), rank: .vertex, metric: 900),
    ]
    for subshape in subshapes {
        #expect(subshape.precedes(occurrence), "\(subshape.rank) outranks the occurrence")
        #expect(occurrence.precedes(subshape) == false)
    }
}
