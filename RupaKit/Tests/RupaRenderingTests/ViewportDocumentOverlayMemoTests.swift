import RupaCore
import SwiftCAD
import Testing
@testable import RupaRendering

/// A viewport derives what the overlay needs from a document alone once per document identity,
/// and what it shares answers exactly as a fresh derivation, charging the same admission.
@Suite @MainActor
struct ViewportDocumentOverlayMemoTests {
    private func groupedBoxes() throws -> (document: DesignDocument, members: [SceneNodeID]) {
        var document = DesignDocument.empty(named: "Frames")
        for index in 0..<2 {
            _ = try document.createExtrudedRectangle(
                name: "Box \(index)", plane: .xy,
                width: .length(0.1, .meter), height: .length(0.1, .meter), depth: .length(0.1, .meter),
                direction: .normal
            )
        }
        let members = document.productMetadata.sceneNodes.filter { $0.value.reference?.kind == .body }.map(\.key)
        #expect(members.count == 2)
        _ = try document.groupSceneNodes(name: "Group", memberIDs: members, origin: Point3D(x: 0.1, y: 0.2, z: 0.3))
        return (document, members)
    }

    @Test(.timeLimit(.minutes(1)))
    func oneDocumentIdentitySharesOneMemo() throws {
        let (document, _) = try groupedBoxes()
        let cache = ViewportDocumentOverlayMemoCache()
        let identity = ViewportSourceIdentity.document(id: document.id, generation: DocumentGeneration(1))
        let first = cache.memo(for: identity, document: document)
        #expect(cache.memo(for: identity, document: document) === first)

        var edited = document
        _ = try edited.createExtrudedRectangle(
            name: "Box 2", plane: .xy,
            width: .length(0.1, .meter), height: .length(0.1, .meter), depth: .length(0.1, .meter),
            direction: .normal
        )
        let next = cache.memo(for: .document(id: document.id, generation: DocumentGeneration(2)), document: edited)
        #expect(next !== first)
        #expect(next.document.productMetadata == edited.productMetadata)
    }

    @Test(.timeLimit(.minutes(1)))
    func sharedPolySplinePatchesAnswerAndChargeAsAFreshDerivation() throws {
        var document = DesignDocument.empty(named: "Patches")
        _ = try document.createPolySplineSurface(
            name: "Surface",
            sourceMesh: Mesh(
                positions: [
                    Point3D(x: 0, y: 0, z: 0), Point3D(x: 0.02, y: 0, z: 0),
                    Point3D(x: 0.02, y: 0.02, z: 0.004), Point3D(x: 0, y: 0.02, z: 0),
                ],
                indices: [0, 1, 2, 0, 2, 3]
            )
        )
        var freshCharge = (items: 0, positions: 0, visits: 0)
        let fresh = try ViewportSpatialOverlayProducer.polySplinePatchDescriptors(document: document) { i, p, v in
            freshCharge = (freshCharge.items + i, freshCharge.positions + p, freshCharge.visits + v)
        }
        #expect(!fresh.isEmpty)
        let memo = ViewportDocumentOverlayMemo(document: document)
        for _ in 0..<2 {
            var charge = (items: 0, positions: 0, visits: 0)
            let shared = try memo.polySplinePatches { i, p, v in
                charge = (charge.items + i, charge.positions + p, charge.visits + v)
            }
            #expect(shared == fresh)
            #expect(charge == freshCharge)
        }
        // A derivation refused by its build's admission is not remembered.
        let refused = ViewportDocumentOverlayMemo(document: document)
        #expect(throws: MeshSourcePresentationRenderError.self) {
            try refused.polySplinePatches { _, _, _ in throw RealityViewportSpatialBatch.exhausted() }
        }
        #expect(try refused.polySplinePatches { _, _, _ in } == fresh)
    }

    @Test(.timeLimit(.minutes(1)))
    func aSharedWalkAnswersAsAFreshOne() throws {
        let (document, members) = try groupedBoxes()
        let memo = ViewportDocumentOverlayMemo(document: document)
        let fresh = try ViewportSceneNodeParentFrames(document: document)
        for _ in 0..<2 {
            let shared = try memo.parentFrames()
            for id in document.productMetadata.sceneNodes.keys {
                #expect(try shared.parentWorldTransform(of: id) == fresh.parentWorldTransform(of: id))
            }
            for member in members {
                #expect(try shared.parentWorldTransform(of: member) != Transform3D.identity)
            }
            #expect(try shared.parentWorldTransform(of: SceneNodeID()) == nil)
        }
    }
}
