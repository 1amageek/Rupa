import CoreGraphics
import Foundation
import RupaCore
import RupaViewportScene
import SwiftCAD
import Testing
@testable import RupaRendering

/// Fillet's radius handle sits at the corner and points between its two curves; dragging it
/// inward commits a Fillet radius and outward a Chamfer distance.
@Suite struct ViewportSketchCornerTreatmentHandleTests {
    @Test func theHandleSitsAtTheCornerPointingBetweenItsCurves() throws {
        let featureID = FeatureID(), firstID = SketchEntityID(), secondID = SketchEntityID(), nodeID = SceneNodeID()
        // An L corner at the origin: one line runs along +x, the other along +y (sketch y is world z).
        let scene = ViewportScene(items: [
            ViewportSceneItem(
                id: "corner-sketch",
                featureID: featureID,
                sceneNodeID: nodeID,
                modelBounds: CGRect(x: 0, y: 0, width: 2, height: 2),
                kind: .sketch(primitives: [
                    .line(entityID: firstID, start: CGPoint(x: 2, y: 0), end: CGPoint(x: 0, y: 0)),
                    .line(entityID: secondID, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: 2)),
                ])
            ),
        ])
        let target = SelectionTarget(
            sceneNodeID: nodeID,
            component: .sketchEntity(.sketchPointHandle(featureID: featureID, entityID: firstID, handle: .lineEnd))
        )
        let handle = ViewportSketchCornerTreatmentHandle(
            target: target,
            ends: SketchCornerTreatmentEnds(
                featureID: featureID,
                selected: .init(entityID: firstID, handle: .lineEnd),
                adjacent: .init(entityID: secondID, handle: .lineStart)
            ),
            signedDistance: -0.25
        )
        let input = ViewportSpatialOverlayProducer.SketchCurveAffordanceSource.RawInput(
            document: .empty(),
            scene: scene,
            selection: SelectionModel(),
            ruler: .standard(for: .meter),
            enabledRoutes: [.sketchCornerTreatment],
            cornerTreatmentHandle: handle
        )
        var meshes: [ViewportSpatialOverlayInput.Mesh] = []
        var paths: [ViewportSpatialOverlayInput.Path] = []
        var labels: [ViewportSpatialOverlayInput.Label] = []
        var markers: [ViewportSpatialOverlayInput.Marker] = []
        var cameraLines: [ViewportSpatialOverlayInput.CameraLine] = []
        var cameraPaths: [ViewportSpatialOverlayInput.CameraPath] = []
        var records: [ViewportSpatialInteractionRecord] = []
        var families: Set<ViewportSpatialOverlayFamily> = []
        try ViewportSpatialOverlayProducer.appendSketchCurveAffordances(
            from: input, meshes: &meshes, paths: &paths, labels: &labels, markers: &markers,
            cameraLines: &cameraLines, cameraPaths: &cameraPaths, interactionRecords: &records,
            activeFamilies: &families, checkpoint: { _, _, _ in }
        )
        #expect(records.count == 1)
        let record = try #require(records.first)
        guard case .sketchCornerTreatment(_, let entityID, let recordTarget, let end, let axis) = record.target else {
            Issue.record("The corner handle used an unexpected prepared target.")
            return
        }
        #expect(entityID == firstID && end == .lineEnd && recordTarget == target)
        #expect(hypot(axis.origin.x, hypot(axis.origin.y, axis.origin.z)) < 1.0e-12)
        let half = 1 / 2.0.squareRoot()
        #expect(abs(axis.direction.x - half) < 1.0e-12 && abs(axis.direction.y) < 1.0e-12 && abs(axis.direction.z - half) < 1.0e-12)
        #expect(axis.baseValue == -0.25)
        #expect(labels.contains { $0.value.text.hasPrefix("Chamfer") })

        // The drag's sign chooses the treatment; a drag back to the start or to the corner is no change.
        let native = try #require(try ViewportNativeAxisInput(record: record))
        guard case .sketchCornerTreatment(let fillet) = try native.commit(value: 0.4) else {
            Issue.record("An inward drag produced no Fillet payload.")
            return
        }
        #expect(fillet.signedDistance == 0.4 && fillet.target == target)
        #expect(try native.value(forWorldDelta: -0.5) < 0)
        #expect(try native.commit(value: -0.25) == nil)
        #expect(try native.commit(value: 0) == nil)
    }

    @Test func aStraightJointHasNoInsideAndNoHandle() throws {
        let featureID = FeatureID(), firstID = SketchEntityID(), secondID = SketchEntityID()
        let scene = ViewportScene(items: [
            ViewportSceneItem(
                id: "straight-sketch",
                featureID: featureID,
                sceneNodeID: SceneNodeID(),
                modelBounds: CGRect(x: 0, y: 0, width: 4, height: 1),
                kind: .sketch(primitives: [
                    .line(entityID: firstID, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 2, y: 0)),
                    .line(entityID: secondID, start: CGPoint(x: 2, y: 0), end: CGPoint(x: 4, y: 0)),
                ])
            ),
        ])
        let input = ViewportSpatialOverlayProducer.SketchCurveAffordanceSource.RawInput(
            document: .empty(),
            scene: scene,
            selection: SelectionModel(),
            ruler: .standard(for: .meter),
            enabledRoutes: [.sketchCornerTreatment],
            cornerTreatmentHandle: ViewportSketchCornerTreatmentHandle(
                target: SelectionTarget(sceneNodeID: SceneNodeID(), component: .object),
                ends: SketchCornerTreatmentEnds(
                    featureID: featureID,
                    selected: .init(entityID: firstID, handle: .lineEnd),
                    adjacent: .init(entityID: secondID, handle: .lineStart)
                ),
                signedDistance: 0.1
            )
        )
        var meshes: [ViewportSpatialOverlayInput.Mesh] = []
        var paths: [ViewportSpatialOverlayInput.Path] = []
        var labels: [ViewportSpatialOverlayInput.Label] = []
        var markers: [ViewportSpatialOverlayInput.Marker] = []
        var cameraLines: [ViewportSpatialOverlayInput.CameraLine] = []
        var cameraPaths: [ViewportSpatialOverlayInput.CameraPath] = []
        var records: [ViewportSpatialInteractionRecord] = []
        var families: Set<ViewportSpatialOverlayFamily> = []
        try ViewportSpatialOverlayProducer.appendSketchCurveAffordances(
            from: input, meshes: &meshes, paths: &paths, labels: &labels, markers: &markers,
            cameraLines: &cameraLines, cameraPaths: &cameraPaths, interactionRecords: &records,
            activeFamilies: &families, checkpoint: { _, _, _ in }
        )
        #expect(records.isEmpty)
    }
}
