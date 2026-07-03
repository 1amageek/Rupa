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
