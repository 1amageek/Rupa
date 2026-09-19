import RupaCore
import RupaViewportScene
import Testing
@testable import RupaRendering

@Test func constructionPlaneOriginDragSnapsPlanarGridAndPreservesDepth() {
    let planeNormal = Vector3D.unitY
    let rawOrigin = Point3D(x: 0.0124, y: 0.0050, z: -0.0076)
    let dragTarget = constructionPlaneSnapDragTarget(
        handle: .origin,
        origin: rawOrigin,
        normal: planeNormal
    )

    let snapped = ViewportConstructionPlaneDragSnapResolver().snappedTarget(
        dragTarget,
        document: .empty(),
        ruler: .standard(for: .millimeter),
        options: SnapResolutionOptions(
            usesGrid: true,
            usesObjects: false,
            gridIntervalMeters: 0.001,
            objectSearchRadiusMeters: 0.0002
        )
    )

    #expect(snapped.handle == .origin)
    #expect(abs(snapped.origin.x - 0.012) <= 1.0e-12)
    #expect(abs(snapped.origin.y - rawOrigin.y) <= 1.0e-12)
    #expect(abs(snapped.origin.z + 0.008) <= 1.0e-12)
    #expect(snapped.normal == planeNormal)
}

@Test func constructionPlaneNormalDragDoesNotUsePlanarGridFallback() {
    let rawNormal = Vector3D(x: 0.0124, y: 0.0030, z: -0.0076)
    let dragTarget = constructionPlaneSnapDragTarget(
        handle: .normal,
        origin: .origin,
        normal: rawNormal
    )

    let snapped = ViewportConstructionPlaneDragSnapResolver().snappedTarget(
        dragTarget,
        document: .empty(),
        ruler: .standard(for: .millimeter),
        options: SnapResolutionOptions(
            usesGrid: true,
            usesObjects: false,
            gridIntervalMeters: 0.001,
            objectSearchRadiusMeters: 0.0002
        )
    )

    #expect(snapped.handle == .normal)
    #expect(snapped.normal == rawNormal)
}

@Test func constructionPlaneNormalDragSnapsToWorldPointCandidate() throws {
    var document = DesignDocument.empty()
    let targetWorldPoint = Point3D(x: 0.020, y: 0.030, z: 0.040)
    _ = try document.addMeasurementAnnotation(
        MeasurementAnnotation(
            name: "Normal Target",
            kind: .distance,
            anchors: [
                .worldPoint(targetWorldPoint, role: .start),
                .worldPoint(Point3D(x: 0.020, y: 0.038, z: 0.040), role: .end),
            ]
        )
    )
    let rawNormal = Vector3D(x: 0.0201, y: 0.0301, z: 0.0401)
    let dragTarget = constructionPlaneSnapDragTarget(
        handle: .normal,
        origin: .origin,
        normal: rawNormal
    )

    let snapped = ViewportConstructionPlaneDragSnapResolver().snappedTarget(
        dragTarget,
        document: document,
        ruler: .standard(for: .millimeter),
        options: SnapResolutionOptions(
            usesGrid: false,
            usesObjects: true,
            constructionPlane: .yz,
            gridIntervalMeters: 0.001,
            objectSearchRadiusMeters: 0.001
        )
    )

    #expect(snapped.handle == .normal)
    #expect(abs(snapped.normal.x - targetWorldPoint.x) <= 1.0e-12)
    #expect(abs(snapped.normal.y - targetWorldPoint.y) <= 1.0e-12)
    #expect(abs(snapped.normal.z - targetWorldPoint.z) <= 1.0e-12)
}

private func constructionPlaneSnapDragTarget(
    handle: ViewportConstructionPlaneHandleKind,
    origin: Point3D,
    normal: Vector3D
) -> ViewportConstructionPlaneDragTarget {
    ViewportConstructionPlaneDragTarget(
        constructionPlaneID: ConstructionPlaneSourceID(),
        sceneNodeID: SceneNodeID(),
        handle: handle,
        origin: origin,
        normal: normal
    )
}
