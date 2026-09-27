import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

/// Mirror copies, cuts, joins or instances selected objects across a world plane through Swift-CAD's
/// mirror feature.
@Suite("Scene mirror")
struct SceneMirrorTests {
    private struct Body {
        var volume: Double
        var minX: Double
        var maxX: Double
    }

    /// A 10 cm cube box and the scene node presenting it.
    private func box() throws -> (DesignDocument, SceneNodeID) {
        var document = DesignDocument.empty()
        let featureID = try document.createExtrudedRectangle(
            name: "Box", plane: .xy, width: .length(0.1, .meter), height: .length(0.1, .meter),
            depth: .length(0.1, .meter), direction: .normal
        )
        let node = try #require(document.productMetadata.sceneNodes.values.first { $0.reference?.featureID == featureID })
        return (document, node.id)
    }

    /// The evaluated body the node presents, in the node's own coordinates.
    private func body(_ nodeID: SceneNodeID, in document: DesignDocument) throws -> Body {
        let featureID = try #require(document.productMetadata.sceneNodes[nodeID]?.reference?.featureID)
        let evaluated = try DocumentEvaluator.modelingDefault(for: document).evaluateExact(document.cadDocument)
        let bodyIDs = evaluated.subshapes.entries.compactMap { key, value -> BodyID? in
            guard key.featureID == featureID, case .body(let id) = value else { return nil }
            return id
        }
        let bodyID = try #require(bodyIDs.first)
        #expect(bodyIDs.count == 1)
        let volume = try evaluated.brep.volume(of: bodyID, tolerance: document.modelingSettings.tolerance)
        let body = try #require(evaluated.brep.bodies[bodyID])
        let faceIDs = body.shellIDs.flatMap { evaluated.brep.shells[$0]?.faceIDs ?? [] }
        let edgeIDs = faceIDs.flatMap { faceID in
            (evaluated.brep.faces[faceID]?.loops ?? []).flatMap { evaluated.brep.loops[$0]?.coedges.map(\.edgeID) ?? [] }
        }
        let xs = edgeIDs.flatMap { edgeID -> [Double] in
            guard let edge = evaluated.brep.edges[edgeID] else { return [] }
            return [edge.startVertexID, edge.endVertexID].compactMap { evaluated.brep.vertices[$0]?.point.x }
        }
        return Body(volume: volume, minX: xs.min() ?? .nan, maxX: xs.max() ?? .nan)
    }

    @Test(.timeLimit(.minutes(1)))
    func mirrorCopiesTheObjectToTheSideTheNormalPointsTo() throws {
        var (document, box) = try box()
        let original = try body(box, in: document)
        let plane = try SceneMirrorPlane(origin: Point3D(x: 0.2, y: 0, z: 0), normal: .unitX)
        let made = try document.mirrorSceneNodes(ids: [box], plane: plane, options: .init())
        let copy = try #require(made.first)
        #expect(made.count == 1)
        #expect(copy != box)
        let mirrored = try body(copy, in: document)
        #expect(abs(mirrored.volume - original.volume) < 1e-12)
        #expect(abs(mirrored.minX - (0.4 - original.maxX)) < 1e-9)
        #expect(abs(mirrored.maxX - (0.4 - original.minX)) < 1e-9)
        let kept = try body(box, in: document)
        #expect(abs(kept.volume - original.volume) < 1e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func cutKeepsTheHalfOppositeTheNormalAndUnionJoinsItWithItsReflection() throws {
        let (base, box) = try box()
        let original = try body(box, in: base)
        let center = (original.minX + original.maxX) / 2
        let plane = try SceneMirrorPlane(origin: Point3D(x: center, y: 0, z: 0), normal: .unitX)

        var cut = base
        let halves = try cut.mirrorSceneNodes(ids: [box], plane: plane, options: .init(cutsAtPlane: true))
        let kept = try body(box, in: cut)
        let reflected = try body(try #require(halves.first), in: cut)
        #expect(abs(kept.volume - original.volume / 2) < 1e-12)
        #expect(abs(kept.maxX - center) < 1e-9)
        #expect(abs(reflected.volume - original.volume / 2) < 1e-12)
        #expect(abs(reflected.minX - center) < 1e-9)

        // Mirroring the half across its cut face restores the whole box as one body.
        var joined = base
        let off = try SceneMirrorPlane(origin: Point3D(x: center, y: 0, z: 0), normal: Vector3D(x: -1, y: 0, z: 0))
        #expect(try joined.mirrorSceneNodes(ids: [box], plane: off, options: .init(cutsAtPlane: true, unionsHalves: true)) == [box])
        let whole = try body(box, in: joined)
        #expect(abs(whole.volume - original.volume) < 1e-12)
        #expect(abs(whole.minX - original.minX) < 1e-9)
        #expect(abs(whole.maxX - original.maxX) < 1e-9)
    }

    @Test(.timeLimit(.minutes(1)))
    func aPlacedObjectIsMirroredAcrossTheWorldPlane() throws {
        var (document, box) = try box()
        let original = try body(box, in: document)
        document.productMetadata.sceneNodes[box]?.localTransform = try Transform3D.translation(Vector3D(x: 1, y: 0, z: 0))
        // The world plane x = 1 + the box center is the box's own center plane.
        let center = (original.minX + original.maxX) / 2
        let plane = try SceneMirrorPlane(origin: Point3D(x: 1 + center, y: 0, z: 0), normal: .unitX)
        try document.mirrorSceneNodes(ids: [box], plane: plane, options: .init(cutsAtPlane: true, unionsHalves: true))
        let whole = try body(box, in: document)
        #expect(abs(whole.volume - original.volume) < 1e-12)
        #expect(abs(whole.minX - original.minX) < 1e-9)
    }

    @Test(.timeLimit(.minutes(1)))
    func makeInstancesPlacesAnInstanceAtTheWorldReflection() throws {
        var (document, box) = try box()
        let plane = try SceneMirrorPlane(origin: Point3D(x: 0.5, y: 0, z: 0), normal: .unitX)
        let made = try document.mirrorSceneNodes(ids: [box], plane: plane, options: .init(makesInstances: true))
        let instanceNode = try #require(made.first.flatMap { document.productMetadata.sceneNodes[$0] })
        #expect(instanceNode.reference?.kind == .componentInstance)
        let instanceID = try #require(instanceNode.reference?.componentInstanceID)
        let instance = try #require(document.productMetadata.componentInstances[instanceID])
        let hierarchy = try SceneNodeHierarchy(metadata: document.productMetadata)
        let occurrence = try hierarchy.worldTransform(of: instanceNode.id).composed(with: instance.localTransform)
        let point = try occurrence.applied(to: Point3D(x: 0.1, y: 0.2, z: 0.3))
        #expect((point - Point3D(x: 0.9, y: 0.2, z: 0.3)).length < 1e-9)
    }

    @Test func planesComeFromAxesAndFreestyleLinesAndRefuseDegenerateInput() throws {
        let negativeY = try SceneMirrorPlane.axis(.y, positive: false, constructionPlane: .xy)
        #expect(negativeY.origin == .origin)
        #expect(negativeY.normal == Vector3D(x: 0, y: -1, z: 0))
        let zOfFront = try SceneMirrorPlane.axis(.z, positive: true, constructionPlane: .zx)
        #expect(zOfFront.normal == .unitY)

        let line = try SceneMirrorPlane.freestyle(start: Point3D(x: 1, y: 0, z: 0), end: Point3D(x: 1, y: 2, z: 0), constructionPlane: .xy)
        #expect(line.origin == Point3D(x: 1, y: 0, z: 0))
        #expect((line.normal - Vector3D(x: -1, y: 0, z: 0)).length < 1e-12)
        #expect(throws: EditorError.self) {
            _ = try SceneMirrorPlane.freestyle(start: .origin, end: Point3D(x: 0, y: 0, z: 1), constructionPlane: .xy)
        }
        #expect(throws: EditorError.self) { _ = try SceneMirrorPlane(origin: .origin, normal: Vector3D(x: 0, y: 0, z: 0)) }

        let reflection = try SceneMirrorPlane(origin: Point3D(x: 0, y: 0, z: 2), normal: .unitZ).reflection()
        #expect(try reflection.applied(to: Point3D(x: 1, y: 1, z: 3)) == Point3D(x: 1, y: 1, z: 1))
    }

    /// A flat 4 cm × 2 cm B-spline sheet over x ∈ [x0, x0 + 0.04] and the scene node presenting it.
    private func sheet(x0: Double) throws -> (DesignDocument, SceneNodeID) {
        var document = DesignDocument.empty()
        let xs = [x0, x0 + 0.04]
        let featureID = try document.createBSplineSurface(name: "Sheet", surface: BSplineSurface3D(
            uDegree: 1, vDegree: 1, uKnots: [0, 0, 1, 1], vKnots: [0, 0, 1, 1],
            controlPoints: [0.0, 0.02].map { y in xs.map { Point3D(x: $0, y: y, z: 0) } }
        ))
        let node = try #require(document.productMetadata.sceneNodes.values.first { $0.reference?.featureID == featureID })
        return (document, node.id)
    }

    /// The faces and x extent of the sheet the node presents.
    private func sheetFaces(_ nodeID: SceneNodeID, in document: DesignDocument) throws -> (faces: Int, minX: Double, maxX: Double) {
        let featureID = try #require(document.productMetadata.sceneNodes[nodeID]?.reference?.featureID)
        let evaluated = try DocumentEvaluator.modelingDefault(for: document).evaluateExact(document.cadDocument)
        let bodyIDs = evaluated.subshapes.entries.compactMap { key, value -> BodyID? in
            guard key.featureID == featureID, case .body(let id) = value else { return nil }
            return id
        }
        #expect(bodyIDs.count == 1)
        let bodyID = try #require(bodyIDs.first)
        let body = try #require(evaluated.brep.bodies[bodyID])
        #expect(body.kind == .sheet)
        let faceIDs = body.shellIDs.flatMap { evaluated.brep.shells[$0]?.faceIDs ?? [] }
        let xs = faceIDs.flatMap { faceID in
            (evaluated.brep.faces[faceID]?.loops ?? []).flatMap { evaluated.brep.loops[$0]?.coedges.map(\.edgeID) ?? [] }
        }.flatMap { edgeID -> [Double] in
            guard let edge = evaluated.brep.edges[edgeID] else { return [] }
            return [edge.startVertexID, edge.endVertexID].compactMap { evaluated.brep.vertices[$0]?.point.x }
        }
        return (faceIDs.count, xs.min() ?? .nan, xs.max() ?? .nan)
    }

    @Test(.timeLimit(.minutes(1)))
    func aSheetIsCopiedAndJoinedAcrossThePlaneAndACutIsRefused() throws {
        let plane = try SceneMirrorPlane(origin: .origin, normal: .unitX)

        var (copied, source) = try sheet(x0: 0.01)
        let copy = try #require(try copied.mirrorSceneNodes(ids: [source], plane: plane, options: .init()).first)
        let reflection = try sheetFaces(copy, in: copied)
        #expect(reflection.faces == 1)
        #expect(abs(reflection.minX + 0.05) < 1e-9)
        #expect(abs(reflection.maxX + 0.01) < 1e-9)

        var (joined, touching) = try sheet(x0: 0)
        _ = try joined.mirrorSceneNodes(ids: [touching], plane: plane, options: .init(unionsHalves: true))
        let union = try sheetFaces(touching, in: joined)
        #expect(union.faces == 2)
        #expect(abs(union.minX + 0.04) < 1e-9)
        #expect(abs(union.maxX - 0.04) < 1e-9)

        var (cut, crossing) = try sheet(x0: -0.01)
        let before = cut
        #expect(throws: EditorError.self) {
            try cut.mirrorSceneNodes(ids: [crossing], plane: plane, options: .init(cutsAtPlane: true))
        }
        #expect(cut.cadDocument.designGraph == before.cadDocument.designGraph)
    }

    @Test func mirrorRefusesConflictingOptionsLockedObjectsAndShearedPlacements() throws {
        var (document, box) = try box()
        let plane = try SceneMirrorPlane(origin: .origin, normal: .unitX)
        #expect(throws: EditorError.self) {
            try document.mirrorSceneNodes(ids: [box], plane: plane, options: .init(unionsHalves: true, makesInstances: true))
        }
        var sheared = document
        sheared.productMetadata.sceneNodes[box]?.localTransform = Transform3D(matrix: try Matrix4x4(values: [
            1, 0.5, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, 0,
            0, 0, 0, 1,
        ]))
        #expect(throws: EditorError.self) {
            try sheared.mirrorSceneNodes(ids: [box], plane: plane, options: .init())
        }
        document.productMetadata.sceneNodes[box]?.isLocked = true
        #expect(throws: EditorError.self) {
            try document.mirrorSceneNodes(ids: [box], plane: plane, options: .init())
        }
    }
}
