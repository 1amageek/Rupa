import CoreGraphics
import RupaCore
import RupaEvaluation
import RupaKit
import RupaViewportScene
import SwiftCAD
import Testing
@testable import RupaRendering

/// A running dialog's value handles: anchored in the scene, dragged along their guide, and
/// registered by the producer at the value a drag in progress shows.
@Suite struct ViewportDialogValueHandleTests {
    @Test func aHandleDragsItsValueScaledToItsGuideAndCommitsItOnRelease() throws {
        // A diameter's dot on the rim moves half as far as the value.
        let input = try #require(try ViewportNativeAxisInput(record: .init(
            target: .dialogValue(id: "pipe.diameter", axis: .init(origin: .origin, direction: .unitZ, baseValue: 0.01,
                                                                  sourceUnitsPerWorldMetre: 2))
        )))
        let value = try input.value(forWorldDelta: 0.002)
        #expect(abs(value - 0.014) < 1e-12)
        #expect(try input.commit(value: value) == .dialogValue(.init(id: "pipe.diameter", valueMeters: value)))
        #expect(try input.commit(value: try input.value(forWorldDelta: 0)) == nil)
    }

    @Test func theProducerRegistersEachHandleAtTheValueADragShows() throws {
        let diameter = ViewportDialogValueHandle(id: "pipe.diameter", anchor: .point(.origin, direction: .unitZ),
                                                 valueMeters: 0.01, worldMetresPerValue: 0.5)
        let thickness = ViewportDialogValueHandle(id: "pipe.thickness", anchor: .point(Point3D(x: 0, y: 0, z: 0.005), direction: .unitZ),
                                                  valueMeters: 0.002, shape: .square)
        let sources = [
            ViewportSpatialOverlayProducer.DialogValueSource(handle: diameter, origin: .origin, direction: .unitZ, activeValueMeters: 0.03),
            ViewportSpatialOverlayProducer.DialogValueSource(handle: thickness, origin: Point3D(x: 0, y: 0, z: 0.005), direction: .unitZ,
                                                             activeValueMeters: nil),
        ]
        var meshes: [ViewportSpatialOverlayInput.Mesh] = []
        var markers: [ViewportSpatialOverlayInput.Marker] = []
        var records: [ViewportSpatialInteractionRecord] = []
        var families: Set<ViewportSpatialOverlayFamily> = []
        try ViewportSpatialOverlayProducer.appendDialogValues(
            sources, meshes: &meshes, markers: &markers, interactionRecords: &records, activeFamilies: &families
        )
        #expect(records.map(\.identity) == [.dialogValue("pipe.diameter"), .dialogValue("pipe.thickness")])
        #expect(meshes.count == 2)
        let dot = try #require(markers.first { $0.value.handleIndex == 0 })
        let square = try #require(markers.first { $0.value.handleIndex == 1 })
        // The dragged diameter of 0.03 shows its dot 0.015 out; the thickness sits 0.002 past the rim.
        #expect(abs(dot.value.anchor.z - 0.015) < 1e-12)
        #expect(dot.value.shape == .sphere)
        #expect(abs(square.value.anchor.z - 0.007) < 1e-12)
        #expect(square.value.shape == .box)
    }

    @MainActor
    @Test func aCurveStartAnchorStandsSquareToTheEdgeAtItsStart() throws {
        let session = EditorSession()
        _ = session.createBSplineSurface(
            name: "Anchor Sheet",
            surface: BSplineSurface3D.cubicBezierPatch(
                bottomLeft: Point3D(x: 0, y: 0, z: 0), bottomRight: Point3D(x: 0.04, y: 0, z: 0),
                topRight: Point3D(x: 0.04, y: 0.02, z: 0), topLeft: Point3D(x: 0, y: 0.02, z: 0)
            )
        )
        let featureID = try #require(session.document.cadDocument.designGraph.order.last)
        let node = try #require(session.document.productMetadata.sceneNodes.first { $0.value.reference == .body(featureID) }?.key)
        let scene = ViewportSceneBuilder().build(
            document: session.document, ruler: RulerConfiguration.standard(for: .millimeter),
            currentEvaluation: try #require(session.currentEvaluation), documentGeneration: session.generation,
            evaluationPolicy: .suppliedOnly
        )
        let item = try #require(scene.firstItem(sceneNodeID: node))
        guard case .body(let component) = item.kind else { Issue.record("The sheet is not drawn as a body."); return }
        let edges = try #require(component.topology?.edges)
        // An edge running along x in the sheet's plane: its guide stands up out of the plane.
        let edge = try #require(edges.first { edge in
            guard let first = edge.displayPoints.first, let last = edge.displayPoints.last else { return false }
            return abs(first.y - last.y) < 1e-9 && abs(first.x - last.x) > 0.01
        })
        let handle = ViewportDialogValueHandle(
            id: "pipe.thickness", anchor: .curveStart(SelectionTarget(sceneNodeID: node, component: .edge(edge.componentID)), offsetMeters: 0.005),
            valueMeters: 0
        )
        let anchor = try #require(try ViewportSpatialOverlayProducer.resolvedDialogValueAnchor(handle, in: scene))
        let start = item.modelTransform.point(try #require(edge.displayPoints.first))
        #expect(abs(abs(anchor.direction.z) - 1) < 1e-9)
        #expect((anchor.origin - (start + anchor.direction * 0.005)).length < 1e-12)
        // An object the scene does not draw anchors nothing.
        let missing = ViewportDialogValueHandle(id: "x", anchor: .curveStart(SelectionTarget(sceneNodeID: SceneNodeID()), offsetMeters: 0),
                                                valueMeters: 0)
        #expect(try ViewportSpatialOverlayProducer.resolvedDialogValueAnchor(missing, in: scene) == nil)
    }

    @MainActor
    @Test func anAngleHandleTurnsAboutItsAxisAndCommitsTheAngle() throws {
        // A circle about z through the origin, measured from x, at 30°; the screen is the xy plane.
        let target = ViewportDialogAngleTarget(id: "pipe.angle", center: .origin, axis: .unitZ,
                                               referencePoint: Point3D(x: 0.01, y: 0, z: 0), angleRadians: .pi / 6)
        let input = try #require(try ViewportNativePatternInput(record: .init(target: .dialogAngle(target))) { point in
            CGPoint(x: point.x * 1000, y: point.y * 1000)
        })
        // From the handle at 30° to the pointer at 120°: a quarter turn on.
        let start = CGPoint(x: 10 * cos(Double.pi / 6), y: 10 * sin(Double.pi / 6))
        let current = CGPoint(x: 10 * cos(2 * Double.pi / 3), y: 10 * sin(2 * Double.pi / 3))
        let value = try #require(try input.value(start: start, current: current))
        guard case .angleRadians(let angle) = value else { Issue.record("Expected an angle."); return }
        #expect(abs(abs(angle - Double.pi / 6) - Double.pi / 2) < 1e-9)
        #expect(try input.commit(value: value) == .dialogAngle(.init(id: "pipe.angle", angleRadians: angle)))
        // An angle may come back to zero.
        let back = CGPoint(x: 10, y: 0)
        guard case .angleRadians(let zero)? = try input.value(start: start, current: back) else { Issue.record("Expected an angle."); return }
        #expect(abs(zero) < 1e-9)
    }

    @Test func theProducerDrawsAnAngleHandlesCircleAndDotAtTheAngleADragShows() throws {
        let handle = ViewportDialogAngleHandle(id: "sweep.twist", anchor: .curveEnd(SelectionTarget(sceneNodeID: SceneNodeID()), offsetMeters: 0),
                                               radiusMeters: 0.01, angleRadians: 0)
        let source = ViewportSpatialOverlayProducer.DialogAngleSource(handle: handle, center: .origin, axis: .unitZ, reference: .unitX,
                                                                      radius: 0.01, activeAngleRadians: Double.pi / 2)
        var meshes: [ViewportSpatialOverlayInput.Mesh] = []
        var markers: [ViewportSpatialOverlayInput.Marker] = []
        var records: [ViewportSpatialInteractionRecord] = []
        var families: Set<ViewportSpatialOverlayFamily> = []
        try ViewportSpatialOverlayProducer.appendDialogAngles(
            [source], meshes: &meshes, markers: &markers, interactionRecords: &records, activeFamilies: &families
        )
        #expect(records.map(\.identity) == [.dialogAngle("sweep.twist")])
        let dot = try #require(markers.first { $0.value.handleIndex == 0 })
        // A quarter turn about z from x: on y.
        #expect(abs(dot.value.anchor.x) < 1e-12 && abs(dot.value.anchor.y - 0.01) < 1e-12)
        let circle = try #require(meshes.first)
        #expect(circle.value.positions.allSatisfy { abs(hypot($0.x, $0.y) - 0.01) < 1e-12 && abs($0.z) < 1e-12 })
    }
}
