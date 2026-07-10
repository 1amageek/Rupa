import CoreGraphics
import RupaCore
import RupaViewportScene
import Testing
@testable import RupaRendering

@Test func constructionPlaneOriginDragSnapsPlanarGridAndPreservesDepth() {
    let layout = constructionPlaneSnapLayout()
    let sourceTarget = constructionPlaneSnapHandleTarget(handle: .origin)
    let rawOrigin = Point3D(x: 0.0124, y: 0.0050, z: -0.0076)
    let dragTarget = ViewportConstructionPlaneDragTarget(
        constructionPlaneID: sourceTarget.constructionPlaneID,
        sceneNodeID: sourceTarget.sceneNodeID,
        handle: .origin,
        origin: rawOrigin,
        normal: sourceTarget.normal
    )

    let snapped = ViewportConstructionPlaneDragSnapResolver().snappedTarget(
        dragTarget,
        sourceTarget: sourceTarget,
        screenPoint: layout.project(rawOrigin),
        document: .empty(),
        ruler: .standard(for: .millimeter),
        options: SnapResolutionOptions(
            usesGrid: true,
            usesObjects: false,
            gridIntervalMeters: 0.001,
            objectSearchRadiusMeters: 0.0002
        ),
        layout: layout
    )

    #expect(snapped.handle == .origin)
    #expect(abs(snapped.origin.x - 0.012) <= 1.0e-12)
    #expect(abs(snapped.origin.y - rawOrigin.y) <= 1.0e-12)
    #expect(abs(snapped.origin.z + 0.008) <= 1.0e-12)
    #expect(snapped.normal == sourceTarget.normal)
}

@Test func constructionPlaneNormalDragDoesNotUsePlanarGridFallback() {
    let layout = constructionPlaneSnapLayout()
    let sourceTarget = constructionPlaneSnapHandleTarget(handle: .normal)
    let rawNormal = Vector3D(x: 0.0124, y: 0.0030, z: -0.0076)
    let dragTarget = ViewportConstructionPlaneDragTarget(
        constructionPlaneID: sourceTarget.constructionPlaneID,
        sceneNodeID: sourceTarget.sceneNodeID,
        handle: .normal,
        origin: sourceTarget.origin,
        normal: rawNormal
    )
    let rawNormalEnd = Point3D(x: rawNormal.x, y: rawNormal.y, z: rawNormal.z)

    let snapped = ViewportConstructionPlaneDragSnapResolver().snappedTarget(
        dragTarget,
        sourceTarget: sourceTarget,
        screenPoint: layout.project(rawNormalEnd),
        document: .empty(),
        ruler: .standard(for: .millimeter),
        options: SnapResolutionOptions(
            usesGrid: true,
            usesObjects: false,
            gridIntervalMeters: 0.001,
            objectSearchRadiusMeters: 0.0002
        ),
        layout: layout
    )

    #expect(snapped.handle == .normal)
    #expect(snapped.normal == rawNormal)
}

@Test func constructionPlaneNormalDragSnapsToWorldPointCandidate() throws {
    let layout = constructionPlaneSnapLayout()
    let sourceTarget = constructionPlaneSnapHandleTarget(handle: .normal)
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
    let dragTarget = ViewportConstructionPlaneDragTarget(
        constructionPlaneID: sourceTarget.constructionPlaneID,
        sceneNodeID: sourceTarget.sceneNodeID,
        handle: .normal,
        origin: sourceTarget.origin,
        normal: rawNormal
    )
    let rawNormalEnd = Point3D(x: rawNormal.x, y: rawNormal.y, z: rawNormal.z)

    let snapped = ViewportConstructionPlaneDragSnapResolver().snappedTarget(
        dragTarget,
        sourceTarget: sourceTarget,
        screenPoint: layout.project(rawNormalEnd),
        document: document,
        ruler: .standard(for: .millimeter),
        options: SnapResolutionOptions(
            usesGrid: false,
            usesObjects: true,
            constructionPlane: .yz,
            gridIntervalMeters: 0.001,
            objectSearchRadiusMeters: 0.001
        ),
        layout: layout
    )

    #expect(snapped.handle == .normal)
    #expect(abs(snapped.normal.x - targetWorldPoint.x) <= 1.0e-12)
    #expect(abs(snapped.normal.y - targetWorldPoint.y) <= 1.0e-12)
    #expect(abs(snapped.normal.z - targetWorldPoint.z) <= 1.0e-12)
}

private func constructionPlaneSnapLayout() -> ViewportLayout {
    ViewportLayout(
        modelBounds: CGRect(x: -0.10, y: -0.10, width: 0.20, height: 0.20),
        size: CGSize(width: 800.0, height: 600.0),
        basis: .axisFront(.z),
        verticalBounds: -0.10 ... 0.10
    )
}

private func constructionPlaneSnapHandleTarget(
    handle: ViewportConstructionPlaneHandleKind
) -> ViewportConstructionPlaneHandleTarget {
    let constructionPlaneID = ConstructionPlaneSourceID()
    let sceneNodeID = SceneNodeID()
    let origin = Point3D.origin
    let normal = Vector3D.unitY
    let normalEnd = Point3D(x: 0.0, y: 0.020, z: 0.0)
    return ViewportConstructionPlaneHandleTarget(
        constructionPlaneID: constructionPlaneID,
        sceneNodeID: sceneNodeID,
        handle: handle,
        origin: origin,
        normal: normal,
        normalEnd: normalEnd,
        corners: [],
        projectedOrigin: CGPoint(x: 400.0, y: 300.0),
        projectedNormalEnd: CGPoint(x: 400.0, y: 280.0)
    )
}
