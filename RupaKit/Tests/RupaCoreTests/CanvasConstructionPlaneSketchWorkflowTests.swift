import SwiftCAD
import Testing
@testable import RupaCore

@MainActor
@Test func canvasClickSketchToolsCreateSketchesOnActiveCustomConstructionPlane() async throws {
    let session = EditorSession()
    let plane = try customCanvasConstructionPlane()
    try activateCanvasConstructionPlane(name: "Canvas CPlane", plane: plane, in: session)
    let activePlane = try #require(session.activeConstructionPlane?.plane)
    let localPoint = Point2D(x: 0.015, y: -0.010)
    let worldPoint = try SketchPlaneCoordinateSystem(plane: activePlane).point(from: localPoint)

    for tool in canvasSketchTools {
        _ = session.activateTool(tool)

        let result = session.activateSelectedToolFromCanvas(
            targetSceneNodeID: nil,
            modelPoint: localPoint,
            modelWorldPoint: worldPoint,
            sketchPlane: activePlane
        )

        #expect(result.tool == tool)
        #expect(result.didMutate)
        #expect(!result.revealsDiagnostics)
        #expect(session.selectedTool == .select)
        let sketch = try latestSketch(in: session)
        #expect(sketch.plane == activePlane)
    }
}

@MainActor
@Test func canvasDragSketchToolsCreateSketchesOnActiveCustomConstructionPlane() async throws {
    let session = EditorSession()
    let plane = try customCanvasConstructionPlane()
    try activateCanvasConstructionPlane(name: "Canvas Drag CPlane", plane: plane, in: session)
    let activePlane = try #require(session.activeConstructionPlane?.plane)
    let coordinateSystem = try SketchPlaneCoordinateSystem(plane: activePlane)
    let startPoint = Point2D(x: 0.004, y: 0.006)
    let endPoint = Point2D(x: 0.024, y: 0.018)
    let startWorldPoint = coordinateSystem.point(from: startPoint)
    let endWorldPoint = coordinateSystem.point(from: endPoint)

    for tool in canvasSketchTools {
        _ = session.activateTool(tool)

        let result = session.activateSelectedToolFromCanvasDrag(
            startModelPoint: startPoint,
            endModelPoint: endPoint,
            sketchPlane: activePlane,
            startWorldPoint: startWorldPoint,
            endWorldPoint: endWorldPoint
        )

        #expect(result.tool == tool)
        #expect(result.didMutate)
        #expect(!result.revealsDiagnostics)
        #expect(session.selectedTool == .select)
        let sketch = try latestSketch(in: session)
        #expect(sketch.plane == activePlane)
    }
}

private let canvasSketchTools: [ModelingTool] = [
    .sketch,
    .polygon,
    .arc,
    .spline,
    .surface,
]

private func customCanvasConstructionPlane() throws -> SketchPlane {
    .plane(
        Plane3D(
            origin: Point3D(x: 0.125, y: -0.040, z: 0.075),
            normal: try Vector3D(x: 0.0, y: 1.0, z: 1.0).normalized(tolerance: 1.0e-12)
        )
    )
}

@MainActor
private func activateCanvasConstructionPlane(
    name: String,
    plane: SketchPlane,
    in session: EditorSession
) throws {
    let result = try #require(session.createConstructionPlane(name: name, plane: plane))
    let id = try #require(result.createdConstructionPlaneID)
    _ = try #require(session.setActiveConstructionPlane(id: id))
}

private func latestSketch(in session: EditorSession) throws -> Sketch {
    let featureID = try #require(session.document.cadDocument.designGraph.order.last)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    let sketch: Sketch?
    if case .sketch(let latestSketch) = feature.operation {
        sketch = latestSketch
    } else {
        sketch = nil
    }
    return try #require(sketch)
}
