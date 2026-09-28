import CoreGraphics
import Foundation
import RupaCore
import RupaViewportScene
import SwiftCAD
import Testing
@testable import RupaRendering

/// Join Curves' endpoint feedback draws each end Core reports at the end, blue-green when it is
/// aligned and purple when it is not, and takes no input.
@Suite struct ViewportJoinEndpointFeedbackTests {
    @Test func endsAreDrawnInTheirJoinColors() throws {
        let featureID = FeatureID(), lineID = SketchEntityID(), splineID = SketchEntityID()
        let scene = ViewportScene(items: [
            ViewportSceneItem(
                id: "join-sketch",
                featureID: featureID,
                sceneNodeID: SceneNodeID(),
                modelBounds: CGRect(x: 0, y: 0, width: 4, height: 2),
                kind: .sketch(primitives: [
                    .line(entityID: lineID, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 2, y: 0)),
                    .cubicSpline(
                        entityID: splineID,
                        points: [CGPoint(x: 2, y: 0), CGPoint(x: 4, y: 2)],
                        controlPoints: [CGPoint(x: 2, y: 0), CGPoint(x: 3, y: 0), CGPoint(x: 4, y: 1), CGPoint(x: 4, y: 2)],
                        sketchPlane: .xy
                    ),
                ])
            ),
        ])
        let feedback = [
            SketchCurveJoinEndpointFeedback(featureID: featureID, entityID: lineID, end: .handle(.lineStart), isAligned: false),
            SketchCurveJoinEndpointFeedback(featureID: featureID, entityID: lineID, end: .handle(.lineEnd), isAligned: true),
            SketchCurveJoinEndpointFeedback(featureID: featureID, entityID: splineID, end: .controlPoint(0), isAligned: true),
            SketchCurveJoinEndpointFeedback(featureID: featureID, entityID: splineID, end: .controlPoint(3), isAligned: false),
        ]
        let input = ViewportSpatialOverlayProducer.SketchCurveAffordanceSource.RawInput(
            document: .empty(),
            scene: scene,
            selection: SelectionModel(),
            ruler: .standard(for: .meter),
            enabledRoutes: [.joinEndpointFeedback],
            joinEndpointFeedback: feedback
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
        #expect(markers.count == 4)
        func color(atX x: Double, z: Double) -> SIMD4<Float>? {
            markers.first { abs($0.value.anchor.x - x) < 1.0e-12 && abs($0.value.anchor.z - z) < 1.0e-12 }?.value.color
        }
        let aligned = ViewportSpatialOverlayProducer.joinAlignedColor, separate = ViewportSpatialOverlayProducer.joinSeparateColor
        #expect(color(atX: 0, z: 0) == separate)
        #expect(color(atX: 4, z: 2) == separate)
        // The line's end and the spline's start meet at (2, 0): both aligned.
        #expect(markers.filter { abs($0.value.anchor.x - 2) < 1.0e-12 }.allSatisfy { $0.value.color == aligned })
        #expect(markers.allSatisfy { $0.value.handleIndex == nil })
    }
}
