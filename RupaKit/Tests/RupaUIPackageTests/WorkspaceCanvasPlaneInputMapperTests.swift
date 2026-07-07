import RupaCore
import RupaRendering
import RupaViewportScene
import SwiftCAD
import Testing
@testable import RupaUI

@Test func workspaceCanvasPlaneInputMapperPreservesStandardPlaneFootprintInput() throws {
    let mapper = WorkspaceCanvasPlaneInputMapper(projectionBasis: .axisFront(.z))
    let point = Point2D(x: 0.12, y: -0.04)

    let result = try mapper.map(
        modelPoint: point,
        modelWorldPoint: nil,
        sketchPlane: .zx
    )

    #expect(result.point == point)
    #expect(result.worldPoint == nil)
}

@Test func workspaceCanvasPlaneInputMapperIntersectsCustomPlaneFromViewRay() throws {
    let plane = SketchPlane.plane(
        Plane3D(
            origin: Point3D(x: 0.0, y: 0.2, z: 0.0),
            normal: .unitY
        )
    )
    let coordinateSystem = try SketchPlaneCoordinateSystem(plane: plane)
    let mapper = WorkspaceCanvasPlaneInputMapper(projectionBasis: .axisFront(.z))

    let result = try mapper.map(
        modelPoint: Point2D(x: 0.04, y: 0.03),
        modelWorldPoint: nil,
        sketchPlane: plane
    )

    let worldPoint = try #require(result.worldPoint)
    let depth = offsetVector(from: coordinateSystem.origin, to: worldPoint).dot(coordinateSystem.normal)
    #expect(abs(depth) <= 1.0e-9)
    #expect(pointIsApproximatelyEqual(result.point, coordinateSystem.project(worldPoint).point))
}

@Test func workspaceCanvasPlaneInputMapperProjectsKnownWorldPointOntoCustomPlane() throws {
    let plane = SketchPlane.plane(
        Plane3D(
            origin: Point3D(x: 0.0, y: 0.2, z: 0.0),
            normal: .unitY
        )
    )
    let coordinateSystem = try SketchPlaneCoordinateSystem(plane: plane)
    let mapper = WorkspaceCanvasPlaneInputMapper(projectionBasis: .axisFront(.z))
    let worldPoint = Point3D(x: 0.03, y: 0.2, z: -0.08)

    let result = try mapper.map(
        modelPoint: Point2D(x: 10.0, y: 10.0),
        modelWorldPoint: worldPoint,
        sketchPlane: plane
    )

    #expect(result.worldPoint == worldPoint)
    #expect(pointIsApproximatelyEqual(result.point, coordinateSystem.project(worldPoint).point))
}

@Test func workspaceCanvasPlaneInputMapperProjectsViewRayAnchorOntoStandardXYPlane() throws {
    let mapper = WorkspaceCanvasPlaneInputMapper(projectionBasis: .axisFront(.z))
    let anchor = Point3D(x: 0.12, y: -0.04, z: 0.0)

    let result = try mapper.map(
        modelPoint: Point2D(x: 99.0, y: 99.0),
        modelWorldPoint: nil,
        viewRayAnchorWorldPoint: anchor,
        sketchPlane: .xy
    )

    #expect(result.worldPoint == anchor)
    #expect(pointIsApproximatelyEqual(result.point, Point2D(x: 0.12, y: -0.04)))
}

@Test func workspaceCanvasPlaneInputMapperProjectsViewRayAnchorOntoStandardZXCanvasPlane() throws {
    let mapper = WorkspaceCanvasPlaneInputMapper(projectionBasis: .axisFront(.y))
    let anchor = Point3D(x: 0.12, y: 0.0, z: -0.04)

    let result = try mapper.map(
        modelPoint: Point2D(x: 99.0, y: 99.0),
        modelWorldPoint: nil,
        viewRayAnchorWorldPoint: anchor,
        sketchPlane: .zx
    )

    #expect(result.worldPoint == anchor)
    #expect(pointIsApproximatelyEqual(result.point, Point2D(x: 0.12, y: -0.04)))
}

@Test func workspaceCanvasPlaneInputMapperIntersectsStandardPlaneFromViewRayAnchor() throws {
    let basis = ViewportProjectionBasis.axisFront(.y)
    let viewNormal = try #require(basis.viewNormal)
    let mapper = WorkspaceCanvasPlaneInputMapper(projectionBasis: basis)
    let anchor = Point3D(x: 0.12, y: 0.0, z: -0.04)

    let result = try mapper.map(
        modelPoint: Point2D(x: 99.0, y: 99.0),
        modelWorldPoint: nil,
        viewRayAnchorWorldPoint: anchor,
        sketchPlane: .xy
    )

    let worldPoint = try #require(result.worldPoint)
    let rayOffset = offsetVector(from: anchor, to: worldPoint)
    let rayCross = rayOffset.cross(viewNormal)

    #expect(abs(worldPoint.z) <= 1.0e-12)
    #expect(pointIsApproximatelyEqual(result.point, Point2D(x: worldPoint.x, y: worldPoint.y)))
    #expect(abs(rayCross.x) <= 1.0e-12)
    #expect(abs(rayCross.y) <= 1.0e-12)
    #expect(abs(rayCross.z) <= 1.0e-12)
    #expect(abs(worldPoint.y - anchor.y) > 1.0e-6)
}

@Test func workspaceCanvasPlaneInputMapperRejectsStandardPlaneParallelToViewRay() throws {
    let mapper = WorkspaceCanvasPlaneInputMapper(projectionBasis: .axisFront(.z))
    let anchor = Point3D(x: 0.12, y: -0.04, z: 0.0)

    do {
        _ = try mapper.map(
            modelPoint: Point2D(x: 99.0, y: 99.0),
            modelWorldPoint: nil,
            viewRayAnchorWorldPoint: anchor,
            sketchPlane: .yz
        )
        Issue.record("Expected mapper to reject a standard plane parallel to the view ray.")
    } catch let failure as WorkspaceCanvasPlaneInputMapper.Failure {
        #expect(failure == .viewRayParallelToPlane)
    }
}

@Test func workspaceCanvasPlaneInputMapperIntersectsCustomPlaneFromViewRayAnchor() throws {
    let plane = SketchPlane.plane(
        Plane3D(
            origin: Point3D(x: 0.0, y: 0.2, z: 0.0),
            normal: .unitY
        )
    )
    let coordinateSystem = try SketchPlaneCoordinateSystem(plane: plane)
    let mapper = WorkspaceCanvasPlaneInputMapper(projectionBasis: .axisFront(.z))
    let anchor = Point3D(x: 0.04, y: 0.0, z: 0.03)

    let result = try mapper.map(
        modelPoint: Point2D(x: 99.0, y: 99.0),
        modelWorldPoint: nil,
        viewRayAnchorWorldPoint: anchor,
        sketchPlane: plane
    )

    let worldPoint = try #require(result.worldPoint)
    let depth = offsetVector(from: coordinateSystem.origin, to: worldPoint).dot(coordinateSystem.normal)
    #expect(abs(depth) <= 1.0e-9)
    #expect(pointIsApproximatelyEqual(result.point, coordinateSystem.project(worldPoint).point))
    #expect(abs(worldPoint.x - anchor.x) <= 1.0e-12)
}

@MainActor
@Test func workspaceCanvasPlaneInputMapperFeedsEditorSessionClickOnCustomPlane() throws {
    let session = EditorSession()
    let plane = try workspaceCanvasCustomPlane()
    _ = try #require(session.createConstructionPlane(name: "Click CPlane", plane: plane))
    let activePlane = try #require(session.activeConstructionPlane?.plane)
    let coordinateSystem = try SketchPlaneCoordinateSystem(plane: activePlane)
    let mapper = WorkspaceCanvasPlaneInputMapper(projectionBasis: .axisFront(.z))
    let canvasInput = try mapper.map(
        modelPoint: Point2D(x: 0.018, y: -0.012),
        modelWorldPoint: nil,
        sketchPlane: activePlane
    )
    let resolvedWorldPoint = try mapper.resolvedWorldPoint(
        for: canvasInput.point,
        snappedWorldPoint: nil,
        fallbackWorldPoint: canvasInput.worldPoint,
        sketchPlane: activePlane
    )
    let worldPoint = try #require(resolvedWorldPoint)

    _ = session.activateTool(.sketch)
    let result = session.activateSelectedToolFromCanvas(
        targetSceneNodeID: nil,
        modelPoint: canvasInput.point,
        modelWorldPoint: worldPoint,
        sketchPlane: activePlane
    )

    #expect(result.didMutate)
    #expect(result.tool == .sketch)
    #expect(session.selectedTool == .select)
    #expect(try latestSketch(in: session).plane == activePlane)
    #expect(pointIsApproximatelyEqual(coordinateSystem.project(worldPoint).point, canvasInput.point))
}

@MainActor
@Test func workspaceCanvasPlaneInputMapperFeedsEditorSessionDragOnCustomPlane() throws {
    let session = EditorSession()
    let plane = try workspaceCanvasCustomPlane()
    _ = try #require(session.createConstructionPlane(name: "Drag CPlane", plane: plane))
    let activePlane = try #require(session.activeConstructionPlane?.plane)
    let coordinateSystem = try SketchPlaneCoordinateSystem(plane: activePlane)
    let mapper = WorkspaceCanvasPlaneInputMapper(projectionBasis: .axisFront(.z))
    let startCanvasInput = try mapper.map(
        modelPoint: Point2D(x: 0.005, y: 0.004),
        modelWorldPoint: nil,
        sketchPlane: activePlane
    )
    let endCanvasInput = try mapper.map(
        modelPoint: Point2D(x: 0.031, y: 0.017),
        modelWorldPoint: nil,
        sketchPlane: activePlane
    )
    let resolvedStartWorldPoint = try mapper.resolvedWorldPoint(
        for: startCanvasInput.point,
        snappedWorldPoint: nil,
        fallbackWorldPoint: startCanvasInput.worldPoint,
        sketchPlane: activePlane
    )
    let resolvedEndWorldPoint = try mapper.resolvedWorldPoint(
        for: endCanvasInput.point,
        snappedWorldPoint: nil,
        fallbackWorldPoint: endCanvasInput.worldPoint,
        sketchPlane: activePlane
    )
    let startWorldPoint = try #require(resolvedStartWorldPoint)
    let endWorldPoint = try #require(resolvedEndWorldPoint)

    _ = session.activateTool(.sketch)
    let result = session.activateSelectedToolFromCanvasDrag(
        startModelPoint: startCanvasInput.point,
        endModelPoint: endCanvasInput.point,
        sketchPlane: activePlane,
        startWorldPoint: startWorldPoint,
        endWorldPoint: endWorldPoint
    )

    #expect(result.didMutate)
    #expect(result.tool == .sketch)
    #expect(session.selectedTool == .select)
    #expect(try latestSketch(in: session).plane == activePlane)
    #expect(pointIsApproximatelyEqual(coordinateSystem.project(startWorldPoint).point, startCanvasInput.point))
    #expect(pointIsApproximatelyEqual(coordinateSystem.project(endWorldPoint).point, endCanvasInput.point))
}

@MainActor
@Test func workspaceCanvasPlaneInputMapperFeedsEditorSessionClickToolsOnCustomPlane() throws {
    let cases = [
        CustomPlaneToolCase(tool: .polygon, expectedCommandName: "createPolygonSketch"),
        CustomPlaneToolCase(tool: .arc, expectedCommandName: "createArcSketch"),
        CustomPlaneToolCase(tool: .spline, expectedCommandName: "createSplineSketch"),
        CustomPlaneToolCase(tool: .surface, expectedCommandName: "createCircleSketch"),
    ]

    for toolCase in cases {
        try assertCustomPlaneCanvasClickCreatesSketch(toolCase)
    }
}

@MainActor
@Test func workspaceCanvasPlaneInputMapperFeedsEditorSessionDragToolsOnCustomPlane() throws {
    let cases = [
        CustomPlaneToolCase(tool: .polygon, expectedCommandName: "createPolygonSketch"),
        CustomPlaneToolCase(tool: .arc, expectedCommandName: "createArcSketch"),
        CustomPlaneToolCase(tool: .spline, expectedCommandName: "createSplineSketch"),
        CustomPlaneToolCase(tool: .surface, expectedCommandName: "createCircleSketch"),
    ]

    for toolCase in cases {
        try assertCustomPlaneCanvasDragCreatesSketch(toolCase)
    }
}

@MainActor
@Test func workspaceCanvasPlaneInputMapperFeedsEditorSessionSolidClickOnCustomPlane() throws {
    let session = EditorSession()
    let plane = try workspaceCanvasCustomPlane()
    _ = try #require(session.createConstructionPlane(name: "Solid Click CPlane", plane: plane))
    let activePlane = try #require(session.activeConstructionPlane?.plane)
    let mapper = WorkspaceCanvasPlaneInputMapper(projectionBasis: .axisFront(.z))
    let canvasInput = try mapper.map(
        modelPoint: Point2D(x: -0.016, y: 0.011),
        modelWorldPoint: nil,
        sketchPlane: activePlane
    )
    let resolvedWorldPoint = try mapper.resolvedWorldPoint(
        for: canvasInput.point,
        snappedWorldPoint: nil,
        fallbackWorldPoint: canvasInput.worldPoint,
        sketchPlane: activePlane
    )
    let worldPoint = try #require(resolvedWorldPoint)

    _ = session.activateTool(.solid)
    let result = session.activateSelectedToolFromCanvas(
        targetSceneNodeID: nil,
        modelPoint: canvasInput.point,
        modelWorldPoint: worldPoint,
        sketchPlane: activePlane
    )

    let sourceSketch = try firstSketch(in: session)
    let extrude = try latestExtrude(in: session)
    #expect(result.commandName == "createExtrudedRectangleFromCorners")
    #expect(result.didMutate)
    #expect(result.tool == .solid)
    #expect(session.selectedTool == .select)
    #expect(sourceSketch.plane == activePlane)
    #expect(extrude.profile.featureID == session.document.cadDocument.designGraph.order.first)
}

@MainActor
@Test func workspaceCanvasPlaneInputMapperFeedsEditorSessionSolidDragOnCustomPlane() throws {
    let session = EditorSession()
    let plane = try workspaceCanvasCustomPlane()
    _ = try #require(session.createConstructionPlane(name: "Solid Drag CPlane", plane: plane))
    let activePlane = try #require(session.activeConstructionPlane?.plane)
    let coordinateSystem = try SketchPlaneCoordinateSystem(plane: activePlane)
    let mapper = WorkspaceCanvasPlaneInputMapper(projectionBasis: .axisFront(.z))
    let startCanvasInput = try mapper.map(
        modelPoint: Point2D(x: -0.024, y: 0.006),
        modelWorldPoint: nil,
        sketchPlane: activePlane
    )
    let endCanvasInput = try mapper.map(
        modelPoint: Point2D(x: 0.018, y: 0.034),
        modelWorldPoint: nil,
        sketchPlane: activePlane
    )
    let startWorldPoint = try #require(
        try mapper.resolvedWorldPoint(
            for: startCanvasInput.point,
            snappedWorldPoint: nil,
            fallbackWorldPoint: startCanvasInput.worldPoint,
            sketchPlane: activePlane
        )
    )
    let endWorldPoint = try #require(
        try mapper.resolvedWorldPoint(
            for: endCanvasInput.point,
            snappedWorldPoint: nil,
            fallbackWorldPoint: endCanvasInput.worldPoint,
            sketchPlane: activePlane
        )
    )

    _ = session.activateTool(.solid)
    let result = session.activateSelectedToolFromCanvasDrag(
        startModelPoint: startCanvasInput.point,
        endModelPoint: endCanvasInput.point,
        sketchPlane: activePlane,
        startWorldPoint: startWorldPoint,
        endWorldPoint: endWorldPoint
    )

    let sourceSketch = try firstSketch(in: session)
    let extrude = try latestExtrude(in: session)
    #expect(result.commandName == "createExtrudedRectangleFromCorners")
    #expect(result.didMutate)
    #expect(result.tool == .solid)
    #expect(session.selectedTool == .select)
    #expect(sourceSketch.plane == activePlane)
    #expect(extrude.profile.featureID == session.document.cadDocument.designGraph.order.first)
    #expect(pointIsApproximatelyEqual(coordinateSystem.project(startWorldPoint).point, startCanvasInput.point))
    #expect(pointIsApproximatelyEqual(coordinateSystem.project(endWorldPoint).point, endCanvasInput.point))
}

@Test func workspaceCanvasPlaneInputMapperRejectsCustomPlaneParallelToViewRay() throws {
    let plane = SketchPlane.plane(
        Plane3D(
            origin: .origin,
            normal: .unitX
        )
    )
    let mapper = WorkspaceCanvasPlaneInputMapper(projectionBasis: .axisFront(.z))

    do {
        _ = try mapper.map(
            modelPoint: Point2D(x: 0.0, y: 0.0),
            modelWorldPoint: nil,
            sketchPlane: plane
        )
        Issue.record("Expected mapper to reject a custom plane parallel to the view ray.")
    } catch let failure as WorkspaceCanvasPlaneInputMapper.Failure {
        #expect(failure == .viewRayParallelToPlane)
    }
}

private struct CustomPlaneToolCase {
    var tool: ModelingTool
    var expectedCommandName: String
}

@MainActor
private func assertCustomPlaneCanvasClickCreatesSketch(
    _ toolCase: CustomPlaneToolCase
) throws {
    let session = EditorSession()
    let plane = try workspaceCanvasCustomPlane()
    _ = try #require(session.createConstructionPlane(name: "\(toolCase.tool.title) Click CPlane", plane: plane))
    let activePlane = try #require(session.activeConstructionPlane?.plane)
    let coordinateSystem = try SketchPlaneCoordinateSystem(plane: activePlane)
    let mapper = WorkspaceCanvasPlaneInputMapper(projectionBasis: .axisFront(.z))
    let canvasInput = try mapper.map(
        modelPoint: Point2D(x: 0.022, y: -0.017),
        modelWorldPoint: nil,
        sketchPlane: activePlane
    )
    let resolvedWorldPoint = try mapper.resolvedWorldPoint(
        for: canvasInput.point,
        snappedWorldPoint: nil,
        fallbackWorldPoint: canvasInput.worldPoint,
        sketchPlane: activePlane
    )
    let worldPoint = try #require(resolvedWorldPoint)

    _ = session.activateTool(toolCase.tool)
    let result = session.activateSelectedToolFromCanvas(
        targetSceneNodeID: nil,
        modelPoint: canvasInput.point,
        modelWorldPoint: worldPoint,
        sketchPlane: activePlane
    )

    #expect(result.commandName == toolCase.expectedCommandName)
    #expect(result.didMutate)
    #expect(result.tool == toolCase.tool)
    #expect(session.selectedTool == .select)
    #expect(try latestSketch(in: session).plane == activePlane)
    #expect(pointIsApproximatelyEqual(coordinateSystem.project(worldPoint).point, canvasInput.point))
}

@MainActor
private func assertCustomPlaneCanvasDragCreatesSketch(
    _ toolCase: CustomPlaneToolCase
) throws {
    let session = EditorSession()
    let plane = try workspaceCanvasCustomPlane()
    _ = try #require(session.createConstructionPlane(name: "\(toolCase.tool.title) Drag CPlane", plane: plane))
    let activePlane = try #require(session.activeConstructionPlane?.plane)
    let coordinateSystem = try SketchPlaneCoordinateSystem(plane: activePlane)
    let mapper = WorkspaceCanvasPlaneInputMapper(projectionBasis: .axisFront(.z))
    let startCanvasInput = try mapper.map(
        modelPoint: Point2D(x: -0.018, y: 0.009),
        modelWorldPoint: nil,
        sketchPlane: activePlane
    )
    let endCanvasInput = try mapper.map(
        modelPoint: Point2D(x: 0.027, y: 0.031),
        modelWorldPoint: nil,
        sketchPlane: activePlane
    )
    let startWorldPoint = try #require(
        try mapper.resolvedWorldPoint(
            for: startCanvasInput.point,
            snappedWorldPoint: nil,
            fallbackWorldPoint: startCanvasInput.worldPoint,
            sketchPlane: activePlane
        )
    )
    let endWorldPoint = try #require(
        try mapper.resolvedWorldPoint(
            for: endCanvasInput.point,
            snappedWorldPoint: nil,
            fallbackWorldPoint: endCanvasInput.worldPoint,
            sketchPlane: activePlane
        )
    )

    _ = session.activateTool(toolCase.tool)
    let result = session.activateSelectedToolFromCanvasDrag(
        startModelPoint: startCanvasInput.point,
        endModelPoint: endCanvasInput.point,
        sketchPlane: activePlane,
        startWorldPoint: startWorldPoint,
        endWorldPoint: endWorldPoint
    )

    #expect(result.commandName == toolCase.expectedCommandName)
    #expect(result.didMutate)
    #expect(result.tool == toolCase.tool)
    #expect(session.selectedTool == .select)
    #expect(try latestSketch(in: session).plane == activePlane)
    #expect(pointIsApproximatelyEqual(coordinateSystem.project(startWorldPoint).point, startCanvasInput.point))
    #expect(pointIsApproximatelyEqual(coordinateSystem.project(endWorldPoint).point, endCanvasInput.point))
}

private func workspaceCanvasCustomPlane() throws -> SketchPlane {
    .plane(
        Plane3D(
            origin: Point3D(x: 0.125, y: -0.040, z: 0.075),
            normal: try Vector3D(x: 0.0, y: 1.0, z: 1.0).normalized(tolerance: 1.0e-12)
        )
    )
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

private func firstSketch(in session: EditorSession) throws -> Sketch {
    let featureID = try #require(session.document.cadDocument.designGraph.order.first)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    let sketch: Sketch?
    if case .sketch(let sourceSketch) = feature.operation {
        sketch = sourceSketch
    } else {
        sketch = nil
    }
    return try #require(sketch)
}

private func latestExtrude(in session: EditorSession) throws -> ExtrudeFeature {
    let featureID = try #require(session.document.cadDocument.designGraph.order.last)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    let extrude: ExtrudeFeature?
    if case .extrude(let latestExtrude) = feature.operation {
        extrude = latestExtrude
    } else {
        extrude = nil
    }
    return try #require(extrude)
}

private func pointIsApproximatelyEqual(
    _ lhs: Point2D,
    _ rhs: Point2D,
    tolerance: Double = 1.0e-9
) -> Bool {
    abs(lhs.x - rhs.x) <= tolerance && abs(lhs.y - rhs.y) <= tolerance
}

private func offsetVector(from start: Point3D, to end: Point3D) -> Vector3D {
    Vector3D(
        x: end.x - start.x,
        y: end.y - start.y,
        z: end.z - start.z
    )
}
