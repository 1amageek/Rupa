import RupaCore
import RupaViewportScene
import SwiftCAD
import Testing
@testable import RupaRendering

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ViewportProfileFaceFrameTests {
    @Test(arguments: [false, true])
    func faceAxesAndRadialEditsFollowSourcePlane(cylinder: Bool) throws {
        for plane in [SketchPlane.xy, .yz, .zx] {
        let session = EditorSession()
        _ = try session.execute(cylinder
            ? .createExtrudedCircle(name: "Cylinder", plane: plane,
                center: .init(x: .length(0, .meter), y: .length(0, .meter)),
                radius: .length(0.05, .meter), depth: .length(0.1, .meter), direction: .normal)
            : .createExtrudedRectangle(name: "Box", plane: plane,
                width: .length(0.1, .meter), height: .length(0.08, .meter),
                depth: .length(0.1, .meter), direction: .normal))
        let document = session.document
        let item = try #require(ViewportSceneBuilder().build(document: document,
            ruler: .standard(for: .meter), evaluationPolicy: .evaluateOnDemand).items.first {
                if case .body = $0.kind { true } else { false }
            })
        let node = try #require(item.sceneNodeID)
        let coordinates = try SketchPlaneCoordinateSystem(plane: plane)
        for face in cylinder ? [ViewportBodyFace.front, .back, .side] : [.front, .back, .left, .right, .top, .bottom] {
            let frame = try ViewportProfileFaceFrame.resolve(item: item, face: face, document: document)
            let expected: Vector3D = switch face {
            case .front: coordinates.normal * -1
            case .back: coordinates.normal
            case .left: coordinates.u * -1
            case .right, .side: coordinates.u
            case .top: coordinates.v
            case .bottom: coordinates.v * -1
            }
            #expect((frame.direction - expected).length < 1e-9)
            let coreFace = try #require(BodyFace(rawValue: face.rawValue))
            let componentID = try #require(try GeneratedTopologySelectionResolver().componentID(
                for: node, bodyFace: coreFace, in: document))
            let target = SelectionTarget(sceneNodeID: node, component: .face(componentID))
            var scaledItem = item
            scaledItem.modelTransform = try ViewportWorldTransformAlgebra.scale(2, about: .origin)
            let scaled = try ViewportProfileFaceFrame.resolve(item: scaledItem, face: face,
                componentID: componentID, document: document)
            let measure = try ViewportOrthographicAffordanceMeasure.isometric(at: scaled.anchor)
            let measured = try scaled.distance(from: measure.projected(scaled.anchor),
                to: measure.projected(scaled.anchor + scaled.direction * 0.004), measure: measure)
            #expect(abs(measured - 0.002) < 1e-9)
            var changed = document
            try changed.offsetBodyFace(target: target, distance: .length(0.002, .meter))
            let after = try #require(ViewportSceneBuilder().build(document: changed,
                ruler: .standard(for: .meter), evaluationPolicy: .evaluateOnDemand).items.first { $0.featureID == item.featureID })
            let moved = try ViewportProfileFaceFrame.resolve(item: after, face: face, document: changed)
            #expect((moved.anchor - frame.anchor - expected * 0.002).length < 1e-8)
            if face == .side {
                let beforeSource = try ObjectDimensionSourceResolver().resolve(target: target, in: document)
                let afterSource = try ObjectDimensionSourceResolver().resolve(target: target, in: changed)
                #expect(abs(try #require(afterSource.radius) - #require(beforeSource.radius) - 0.002) < 1e-9)
                #expect(afterSource.sizeY == beforeSource.sizeY)
                var refused = document
                #expect(throws: EditorError.self) {
                    try refused.offsetBodyFace(target: target, distance: .length(-1, .meter))
                }
                #expect(refused.productMetadata == document.productMetadata)
            }
            guard case .body(let body) = item.kind else { return }
            let highlight = try ViewportSpatialOverlayProducer.selectedFaceMesh(componentID, item: item,
                component: body, color: .init(0, 1, 1, 0.3))
            let topology = try #require(body.topology)
            #expect(highlight.indices.count == topology.meshFaceRuns.filter { $0.componentID == componentID }
                .reduce(0) { $0 + $1.triangleRange.count * 3 })
            #expect(!highlight.indices.isEmpty)
            let sourceMesh = try #require(body.mesh)
            #expect(highlight.positions == sourceMesh.positions)
        }
        }
    }
}
