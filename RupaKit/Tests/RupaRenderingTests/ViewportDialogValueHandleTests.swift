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
}
