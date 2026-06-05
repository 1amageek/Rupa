import CoreGraphics
import RupaCore
import RupaRendering
import SwiftCAD
import Testing

@MainActor
@Test func viewportSceneBuilderCreatesSelectableSketchAndBodyItems() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())

    let scene = ViewportSceneBuilder().build(document: session.document)

    #expect(scene.items.count == 2)
    #expect(scene.items.contains { item in
        if case .sketch = item.kind {
            return true
        }
        return false
    })
    #expect(scene.items.contains { item in
        if case .body = item.kind {
            return true
        }
        return false
    })
    #expect(scene.modelBounds != nil)
}

@MainActor
@Test func viewportHitTesterSelectsBodyInteriorAndSketchEdges() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let scene = ViewportSceneBuilder().build(document: session.document)
    let size = CGSize(width: 800.0, height: 600.0)
    let layout = try #require(ViewportLayout(scene: scene, size: size))
    let bodyItem = try #require(scene.items.first { item in
        if case .body = item.kind {
            return true
        }
        return false
    })
    let sketchItem = try #require(scene.items.first { item in
        if case .sketch = item.kind {
            return true
        }
        return false
    })

    let bodyPoint = layout.project(
        CGPoint(
            x: bodyItem.modelBounds.midX,
            y: bodyItem.modelBounds.midY
        )
    )
    let bodyHit = ViewportHitTester().hitTest(
        point: bodyPoint,
        in: scene,
        size: size
    )

    let sketchEdgePoint = layout.project(
        CGPoint(
            x: sketchItem.modelBounds.minX,
            y: sketchItem.modelBounds.midY
        )
    )
    let sketchHit = ViewportHitTester().hitTest(
        point: sketchEdgePoint,
        in: scene,
        size: size
    )

    #expect(bodyHit?.featureID == bodyItem.featureID)
    #expect(bodyHit?.kind == .body)
    #expect(bodyHit?.bodyFace != nil)
    #expect(sketchHit == ViewportHit(featureID: sketchItem.featureID, kind: .sketch))
}

@MainActor
@Test func viewportHitTesterReturnsNilForBackground() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let scene = ViewportSceneBuilder().build(document: session.document)

    let hit = ViewportHitTester().hitTest(
        point: CGPoint(x: 8.0, y: 8.0),
        in: scene,
        size: CGSize(width: 800.0, height: 600.0)
    )

    #expect(hit == nil)
}

@Test func viewportLayoutUnprojectsProjectedMicrometerModelPoint() {
    let bounds = CGRect(
        x: -0.000_002,
        y: -0.000_003,
        width: 0.000_004,
        height: 0.000_006
    )
    let size = CGSize(width: 800.0, height: 600.0)
    let layout = ViewportLayout(modelBounds: bounds, size: size)
    let modelPoint = CGPoint(x: 0.000_001, y: -0.000_002)
    let projectedPoint = layout.project(modelPoint)
    let unprojectedPoint = layout.unproject(projectedPoint)
    let expectedBounds = projectedBounds(
        width: bounds.width,
        height: bounds.height,
        basis: layout.basis
    )
    let expectedScale = min(
        (size.width - 180.0) / expectedBounds.width,
        (size.height - 140.0) / expectedBounds.height
    )

    #expect(abs(layout.scale - expectedScale) < expectedScale * 1.0e-12)
    #expect(abs(unprojectedPoint.x - modelPoint.x) < 1.0e-15)
    #expect(abs(unprojectedPoint.y - modelPoint.y) < 1.0e-15)
}

@Test func viewportLayoutProjectsFootprintAlongCoordinateGridBasis() {
    let bounds = CGRect(
        x: -0.02,
        y: -0.01,
        width: 0.04,
        height: 0.02
    )
    let layout = ViewportLayout(
        modelBounds: bounds,
        size: CGSize(width: 800.0, height: 600.0)
    )
    let footprint = layout.projectedFootprint(bounds)
    let grid = ViewportProjectionBasis.isometric

    let xEdge = CGVector(
        dx: footprint.bottomRight.x - footprint.bottomLeft.x,
        dy: footprint.bottomRight.y - footprint.bottomLeft.y
    )
    let zEdge = CGVector(
        dx: footprint.topLeft.x - footprint.bottomLeft.x,
        dy: footprint.topLeft.y - footprint.bottomLeft.y
    )

    #expect(isParallel(xEdge, grid.xDirection))
    #expect(isParallel(zEdge, grid.zDirection))
    #expect(footprint.bounds.width > 0.0)
    #expect(footprint.bounds.height > 0.0)
}

@Test func viewportModelCoordinateMapperProvidesEmptyDocumentDragPlane() {
    var document = DesignDocument.empty()
    document.setDisplayUnit(.micrometer)
    let mapper = ViewportModelCoordinateMapper(
        document: document,
        size: CGSize(width: 800.0, height: 600.0)
    )
    let centerPoint = mapper.modelPoint(for: CGPoint(x: 400.0, y: 300.0))
    let drag = mapper.modelDrag(
        from: CGPoint(x: 360.0, y: 320.0),
        to: CGPoint(x: 440.0, y: 280.0)
    )

    #expect(abs(mapper.layout.modelBounds.width - 0.000_2) < 1.0e-18)
    #expect(abs(mapper.layout.modelBounds.height - 0.000_2) < 1.0e-18)
    #expect(abs(centerPoint.x) < 1.0e-15)
    #expect(abs(centerPoint.y) < 1.0e-15)
    #expect(drag.start != drag.end)
}

@MainActor
@Test func viewportSceneProjectsZXCanvasSketchBackToCanvasCoordinates() async throws {
    let session = EditorSession()
    session.selectTool(.sketch)

    _ = session.activateSelectedToolFromCanvas(
        targetSceneNodeID: nil,
        modelPoint: Point2D(x: 0.03, y: 0.04),
        sketchPlane: .zx
    )

    let scene = ViewportSceneBuilder().build(document: session.document)
    let item = try #require(scene.items.first)

    #expect(abs(item.modelBounds.midX - 0.03) < 1.0e-12)
    #expect(abs(item.modelBounds.midY - 0.04) < 1.0e-12)
}

@MainActor
@Test func viewportMapperKeepsCanvasPointStableAfterCanvasCreation() async throws {
    let session = EditorSession()
    let size = CGSize(width: 800.0, height: 600.0)
    let clickPoint = CGPoint(x: 520.0, y: 260.0)
    let initialMapper = ViewportModelCoordinateMapper(
        document: session.document,
        size: size
    )
    let modelPoint = initialMapper.modelPoint(for: clickPoint)

    session.selectTool(.sketch)
    _ = session.activateSelectedToolFromCanvas(
        targetSceneNodeID: nil,
        modelPoint: modelPoint,
        sketchPlane: .zx
    )

    let finalMapper = ViewportModelCoordinateMapper(
        document: session.document,
        size: size
    )
    let finalPoint = finalMapper.layout.project(
        CGPoint(x: modelPoint.x, y: modelPoint.y)
    )

    #expect(abs(finalPoint.x - clickPoint.x) < 1.0e-9)
    #expect(abs(finalPoint.y - clickPoint.y) < 1.0e-9)
}

@Test func viewportCanvasDragPlaceholderUsesCoordinateAlignedFootprintOnEmptyDocument() throws {
    var document = DesignDocument.empty()
    document.setDisplayUnit(.millimeter)
    let mapper = ViewportModelCoordinateMapper(
        document: document,
        size: CGSize(width: 800.0, height: 600.0)
    )
    let drag = mapper.modelDrag(
        from: CGPoint(x: 320.0, y: 360.0),
        to: CGPoint(x: 500.0, y: 280.0)
    )
    let placeholder = try #require(
        ViewportCanvasDragPlaceholder(
            drag: drag,
            layout: mapper.layout
        )
    )
    let xEdge = CGVector(
        dx: placeholder.footprint.bottomRight.x - placeholder.footprint.bottomLeft.x,
        dy: placeholder.footprint.bottomRight.y - placeholder.footprint.bottomLeft.y
    )
    let zEdge = CGVector(
        dx: placeholder.footprint.topLeft.x - placeholder.footprint.bottomLeft.x,
        dy: placeholder.footprint.topLeft.y - placeholder.footprint.bottomLeft.y
    )

    #expect(placeholder.modelBounds.width > 0.0)
    #expect(placeholder.modelBounds.height > 0.0)
    #expect(isParallel(xEdge, mapper.layout.basis.xDirection))
    #expect(isParallel(zEdge, mapper.layout.basis.zDirection))
    #expect(placeholder.footprint.handlePoints.count == 8)
}

@Test func viewportProjectedGridCreatesCoordinateParallelLines() {
    var document = DesignDocument.empty()
    document.setDisplayUnit(.millimeter)
    let grid = ViewportProjectedGrid(
        document: document,
        size: CGSize(width: 800.0, height: 600.0)
    )
    let xLines = grid.lines(for: .x)
    let zLines = grid.lines(for: .z)
    let firstXVector = vector(for: xLines[0])
    let firstZVector = vector(for: zLines[0])

    #expect(!xLines.isEmpty)
    #expect(!zLines.isEmpty)
    #expect(xLines.contains { $0.isMajor })
    #expect(zLines.contains { $0.isMajor })
    #expect(grid.majorStepMeters >= document.ruler.majorTickMeters)
    #expect(grid.minorStepMeters >= document.ruler.minorTickMeters)
    #expect(abs(firstXVector.dx) > 0.0)
    #expect(abs(firstXVector.dy) > 0.0)
    #expect(abs(firstZVector.dx) > 0.0)
    #expect(abs(firstZVector.dy) > 0.0)
    #expect(firstXVector.dx * firstZVector.dx < 0.0)
    #expect(!isParallel(firstXVector, firstZVector))
    #expect(xLines.prefix(12).allSatisfy { isParallel(vector(for: $0), firstXVector) })
    #expect(zLines.prefix(12).allSatisfy { isParallel(vector(for: $0), firstZVector) })
}

private func vector(for line: ViewportProjectedGrid.Line) -> CGVector {
    CGVector(
        dx: line.end.x - line.start.x,
        dy: line.end.y - line.start.y
    )
}

private func isParallel(_ lhs: CGVector, _ rhs: CGVector) -> Bool {
    let crossProduct = lhs.dx * rhs.dy - lhs.dy * rhs.dx
    let scale = max(hypot(lhs.dx, lhs.dy) * hypot(rhs.dx, rhs.dy), 1.0)
    return abs(crossProduct / scale) < 1.0e-9
}

private func projectedBounds(
    width: CGFloat,
    height: CGFloat,
    basis: ViewportProjectionBasis
) -> CGRect {
    let points = [
        CGPoint(x: 0.0, y: 0.0),
        CGPoint(x: basis.xDirection.dx * width, y: basis.xDirection.dy * width),
        CGPoint(x: basis.zDirection.dx * height, y: basis.zDirection.dy * height),
        CGPoint(
            x: basis.xDirection.dx * width + basis.zDirection.dx * height,
            y: basis.xDirection.dy * width + basis.zDirection.dy * height
        ),
    ]
    let minX = points.map(\.x).min() ?? 0.0
    let minY = points.map(\.y).min() ?? 0.0
    let maxX = points.map(\.x).max() ?? 0.0
    let maxY = points.map(\.y).max() ?? 0.0
    return CGRect(
        x: minX,
        y: minY,
        width: maxX - minX,
        height: maxY - minY
    )
}
