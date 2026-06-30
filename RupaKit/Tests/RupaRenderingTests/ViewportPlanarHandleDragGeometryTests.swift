import CoreGraphics
import RupaCore
import SwiftCAD
import Testing
@testable import RupaRendering

@Test func viewportPlanarHandleDragGeometryKeepsAxisDeltaLocalUnderTransform() throws {
    let layout = planarHandleDragLayout()
    let geometry = ViewportPlanarHandleDragGeometry(
        localPoint: .origin,
        modelTransform: try planarHandleDragTransform(scale: 2.0, translationX: 0.006)
    )
    let start = geometry.projectedPoint(layout: layout)
    let current = layout.project(Point3D(x: 0.008, y: 0.0, z: 0.0))

    let axisDelta = geometry.localDelta(axis: .x, start: start, current: current, layout: layout)
    let localAxisDelta = geometry.localDelta(
        direction: Vector3D(x: 1.0, y: 0.0, z: 0.0),
        start: start,
        current: current,
        layout: layout
    )
    let movedDisplayPoint = geometry.displayPoint(offsetByLocalDelta: axisDelta)

    #expect(abs(geometry.displayPoint.x - 0.006) < 1.0e-12)
    #expect(abs(axisDelta.x - 0.001) < 1.0e-12)
    #expect(abs(axisDelta.y) < 1.0e-12)
    #expect(abs(axisDelta.z) < 1.0e-12)
    #expect(abs(localAxisDelta.x - 0.001) < 1.0e-12)
    #expect(abs(movedDisplayPoint.x - 0.008) < 1.0e-12)
}

@Test func viewportPlanarHandleDragGeometryConvertsPlanarDeltaBackToLocal() throws {
    let layout = planarHandleDragLayout()
    let geometry = ViewportPlanarHandleDragGeometry(
        localPoint: .origin,
        modelTransform: try planarHandleDragTransform(scale: 2.0, translationX: 0.006)
    )
    let start = geometry.projectedPoint(layout: layout)
    let current = layout.project(Point3D(x: 0.008, y: 0.0, z: 0.0))

    let delta = geometry.localPlanarDelta(start: start, current: current, layout: layout)

    #expect(abs(delta.x - 0.001) < 1.0e-12)
    #expect(abs(delta.y) < 1.0e-12)
    #expect(abs(delta.z) < 1.0e-12)
}

@Test func viewportTransformInverseRoundTripsRotatedVectors() throws {
    let transform = Transform3D(matrix: try Matrix4x4(values: [
        0.0, 0.0, 1.0, 0.0,
        0.0, 1.0, 0.0, 0.0,
        -1.0, 0.0, 0.0, 0.0,
        0.0, 0.0, 0.0, 1.0,
    ]))
    let vector = Vector3D(x: 0.002, y: 0.003, z: 0.004)
    let transformed = transform.viewportTransformedVector(vector)
    let inverted = try #require(transform.viewportInverseTransformedVector(transformed))

    #expect(abs(inverted.x - vector.x) < 1.0e-12)
    #expect(abs(inverted.y - vector.y) < 1.0e-12)
    #expect(abs(inverted.z - vector.z) < 1.0e-12)
}

private func planarHandleDragLayout() -> ViewportLayout {
    ViewportLayout(
        modelBounds: CGRect(x: -0.002, y: -0.002, width: 0.020, height: 0.020),
        size: CGSize(width: 800.0, height: 600.0)
    )
}

private func planarHandleDragTransform(
    scale: Double,
    translationX: Double
) throws -> Transform3D {
    Transform3D(matrix: try Matrix4x4(values: [
        scale, 0.0, 0.0, 0.0,
        0.0, scale, 0.0, 0.0,
        0.0, 0.0, scale, 0.0,
        translationX, 0.0, 0.0, 1.0,
    ]))
}
