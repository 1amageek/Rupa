import CoreGraphics
import Testing
import RupaCore
import RupaViewportScene
@testable import RupaRendering

@Test func viewportSectionMeshClipperRetainsTrianglesOnRequestedPlaneSide() {
    let mesh = ViewportBodyMesh(
        positions: [
            Point3D(x: 1.0, y: 0.0, z: 0.0),
            Point3D(x: 1.0, y: 1.0, z: 0.0),
            Point3D(x: 1.0, y: 0.0, z: 1.0),
            Point3D(x: -1.0, y: 0.0, z: 0.0),
            Point3D(x: -1.0, y: 1.0, z: 0.0),
            Point3D(x: -1.0, y: 0.0, z: 1.0),
            Point3D(x: -1.0, y: 0.0, z: 0.0),
            Point3D(x: 1.0, y: 0.0, z: 0.0),
            Point3D(x: 0.0, y: 1.0, z: 0.0),
        ],
        indices: [
            0, 1, 2,
            3, 4, 5,
            6, 7, 8,
        ]
    )
    let item = ViewportSceneItem(
        id: "mesh-body",
        featureID: FeatureID(),
        modelBounds: CGRect(x: -1.0, y: -1.0, width: 2.0, height: 2.0),
        kind: .body(
            component: ViewportBodyComponent(
                bodyID: "body",
                sizeXMeters: 2.0,
                sizeYMeters: 1.0,
                sizeZMeters: 1.0,
                yMinMeters: 0.0,
                yMaxMeters: 1.0,
                mesh: mesh
            )
        )
    )
    let plane = SectionAnalysisResult.Plane(
        sourceKind: .sketchPlane,
        sourceID: nil,
        sourceName: nil,
        origin: .origin,
        normal: .unitX,
        u: .unitY,
        v: .unitZ
    )
    let clipper = ViewportSectionMeshClipper()

    #expect(clipper.includedTriangleCount(
        mesh: mesh,
        item: item,
        plane: plane,
        retaining: .front,
        toleranceMeters: 1.0e-8
    ) == 2)
    #expect(clipper.includedTriangleCount(
        mesh: mesh,
        item: item,
        plane: plane,
        retaining: .behind,
        toleranceMeters: 1.0e-8
    ) == 2)
}

@Test func viewportSectionMeshClipperClipsCrossingTriangleIntoRetainedPolygon() {
    let item = viewportSectionMeshClipperBodyItem()
    let plane = viewportSectionMeshClipperPlane()
    let clipper = ViewportSectionMeshClipper()

    let frontPolygon = clipper.clippedTriangle(
        first: Point3D(x: -1.0, y: 0.0, z: 0.0),
        second: Point3D(x: 1.0, y: 0.0, z: 0.0),
        third: Point3D(x: 1.0, y: 1.0, z: 0.0),
        item: item,
        plane: plane,
        retaining: .front,
        toleranceMeters: 0.0
    )
    let behindPolygon = clipper.clippedTriangle(
        first: Point3D(x: -1.0, y: 0.0, z: 0.0),
        second: Point3D(x: 1.0, y: 0.0, z: 0.0),
        third: Point3D(x: 1.0, y: 1.0, z: 0.0),
        item: item,
        plane: plane,
        retaining: .behind,
        toleranceMeters: 0.0
    )

    #expect(frontPolygon.count == 4)
    #expect(frontPolygon.allSatisfy { $0.x >= -1.0e-12 })
    #expect(frontPolygon.contains { abs($0.x) <= 1.0e-12 && abs($0.y) <= 1.0e-12 })
    #expect(frontPolygon.contains { abs($0.x) <= 1.0e-12 && abs($0.y - 0.5) <= 1.0e-12 })
    #expect(behindPolygon.count == 3)
    #expect(behindPolygon.allSatisfy { $0.x <= 1.0e-12 })
}

@Test func viewportSectionMeshClipperAppliesItemTransformBeforeClipping() throws {
    var item = viewportSectionMeshClipperBodyItem()
    item.modelTransform = try viewportSectionMeshClipperTranslationTransform(x: 10.0)
    let plane = SectionAnalysisResult.Plane(
        sourceKind: .sketchPlane,
        sourceID: nil,
        sourceName: nil,
        origin: Point3D(x: 11.0, y: 0.0, z: 0.0),
        normal: .unitX,
        u: .unitY,
        v: .unitZ
    )
    let clipper = ViewportSectionMeshClipper()

    let polygon = clipper.clippedTriangle(
        first: Point3D(x: 0.0, y: 0.0, z: 0.0),
        second: Point3D(x: 2.0, y: 0.0, z: 0.0),
        third: Point3D(x: 2.0, y: 1.0, z: 0.0),
        item: item,
        plane: plane,
        retaining: .front,
        toleranceMeters: 0.0
    )

    #expect(polygon.count == 4)
    #expect(polygon.allSatisfy { $0.x >= 11.0 - 1.0e-12 })
    #expect(polygon.contains { abs($0.x - 11.0) <= 1.0e-12 && abs($0.y) <= 1.0e-12 })
    #expect(polygon.contains { abs($0.x - 11.0) <= 1.0e-12 && abs($0.y - 0.5) <= 1.0e-12 })
}

private func viewportSectionMeshClipperBodyItem() -> ViewportSceneItem {
    ViewportSceneItem(
        id: "mesh-body",
        featureID: FeatureID(),
        modelBounds: CGRect(x: -1.0, y: -1.0, width: 2.0, height: 2.0),
        kind: .body(
            component: ViewportBodyComponent(
                bodyID: "body",
                sizeXMeters: 2.0,
                sizeYMeters: 1.0,
                sizeZMeters: 1.0,
                yMinMeters: 0.0,
                yMaxMeters: 1.0
            )
        )
    )
}

private func viewportSectionMeshClipperPlane() -> SectionAnalysisResult.Plane {
    SectionAnalysisResult.Plane(
        sourceKind: .sketchPlane,
        sourceID: nil,
        sourceName: nil,
        origin: .origin,
        normal: .unitX,
        u: .unitY,
        v: .unitZ
    )
}

private func viewportSectionMeshClipperTranslationTransform(
    x: Double
) throws -> Transform3D {
    Transform3D(matrix: try Matrix4x4(values: [
        1.0, 0.0, 0.0, 0.0,
        0.0, 1.0, 0.0, 0.0,
        0.0, 0.0, 1.0, 0.0,
        x, 0.0, 0.0, 1.0,
    ]))
}
