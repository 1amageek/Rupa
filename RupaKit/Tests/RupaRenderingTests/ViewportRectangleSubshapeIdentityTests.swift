import CoreGraphics
import RupaCore
import RupaViewportScene
import SwiftCAD
import Testing
@testable import RupaRendering

/// The rectangle sub-shape query holds one admitted set for the whole scene, so
/// the identity it keys by decides whether the placements of a shared feature
/// survive. `ViewportSceneBuilder` gives every `SceneNodeID` that places a
/// feature its own scene item over the same prepared topology, so those items
/// carry identical `SelectionComponentID`s and only the placement tells them
/// apart.
@MainActor
@Suite("Viewport rectangle sub-shape identity")
struct ViewportRectangleSubshapeIdentityTests {
    private static let sharedFeatureID = FeatureID()

    private static let faceComponent = SelectionComponent.face(
        .generatedTopology(SubshapeID(featureID: sharedFeatureID, role: "face", ordinal: 3))
    )

    private static let edgeComponent = SelectionComponent.edge(
        .generatedTopology(SubshapeID(featureID: sharedFeatureID, role: "edge", ordinal: 7))
    )

    @Test("Every placement of one shared feature is reported")
    func reportsEveryPlacementOfOneSharedFeature() throws {
        let firstPlacement = SceneNodeID()
        let secondPlacement = SceneNodeID()
        var hits: [ViewportHit] = []
        var admitted: Set<SelectionTarget> = []
        for sceneNodeID in [firstPlacement, secondPlacement] {
            Viewport.appendRectangleSubshapeHits(
                [Self.faceComponent, Self.edgeComponent],
                featureID: Self.sharedFeatureID,
                sceneNodeID: sceneNodeID,
                into: &hits,
                admitted: &admitted
            )
        }
        #expect(hits.count == 4)
        for sceneNodeID in [firstPlacement, secondPlacement] {
            #expect(
                hits.contains {
                    $0.sceneNodeID == sceneNodeID && $0.selectionComponent == Self.faceComponent
                }
            )
            #expect(
                hits.contains {
                    $0.sceneNodeID == sceneNodeID && $0.selectionComponent == Self.edgeComponent
                }
            )
        }
        #expect(hits.allSatisfy { $0.featureID == Self.sharedFeatureID })
        #expect(hits.allSatisfy { $0.kind == .body })
    }

    @Test("One placement reports each sub-shape once")
    func reportsEachSubshapeOncePerPlacement() throws {
        let sceneNodeID = SceneNodeID()
        var hits: [ViewportHit] = []
        var admitted: Set<SelectionTarget> = []
        Viewport.appendRectangleSubshapeHits(
            [Self.faceComponent, Self.faceComponent, Self.edgeComponent],
            featureID: Self.sharedFeatureID,
            sceneNodeID: sceneNodeID,
            into: &hits,
            admitted: &admitted
        )
        Viewport.appendRectangleSubshapeHits(
            [Self.faceComponent],
            featureID: Self.sharedFeatureID,
            sceneNodeID: sceneNodeID,
            into: &hits,
            admitted: &admitted
        )
        #expect(hits.count == 2)
        #expect(hits.filter { $0.selectionComponent == Self.faceComponent }.count == 1)
        #expect(hits.filter { $0.selectionComponent == Self.edgeComponent }.count == 1)
    }

    @Test("A component naming no generated sub-shape is not reported")
    func skipsComponentsWithoutGeneratedSubshapeIdentity() throws {
        var hits: [ViewportHit] = []
        var admitted: Set<SelectionTarget> = []
        Viewport.appendRectangleSubshapeHits(
            [
                .object,
                .sketchEntity(SelectionComponentID(rawValue: "sketchEntity:probe")),
                .region(SelectionComponentID(rawValue: "profileRegion:probe")),
                .constructionPlane(ConstructionPlaneSourceID()),
                Self.faceComponent,
            ],
            featureID: Self.sharedFeatureID,
            sceneNodeID: SceneNodeID(),
            into: &hits,
            admitted: &admitted
        )
        #expect(hits.count == 1)
        #expect(hits.first?.selectionComponent == Self.faceComponent)
    }
}
