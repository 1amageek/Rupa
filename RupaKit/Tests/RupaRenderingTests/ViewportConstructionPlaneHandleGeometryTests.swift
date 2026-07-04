import CoreGraphics
import RupaCore
import RupaViewportScene
import Testing
@testable import RupaRendering

@Test func constructionPlaneHandleGeometryBuildsSelectedPlaneHandles() throws {
    let fixture = try constructionPlaneHandleFixture()
    let targets = ViewportConstructionPlaneHandleGeometry().targets(
        document: fixture.document,
        selection: fixture.selection,
        layout: fixture.layout
    )

    #expect(targets.count == 2)
    #expect(targets.map(\.handle).contains(.origin))
    #expect(targets.map(\.handle).contains(.normal))
    #expect(targets.allSatisfy { $0.constructionPlaneID == fixture.entry.id })
    #expect(targets.allSatisfy { $0.sceneNodeID == fixture.entry.sceneNodeID })
    #expect(targets.allSatisfy { $0.corners.count == 4 })
}

@Test func constructionPlaneHandleGeometryHitTestsOriginAndNormalHandles() throws {
    let fixture = try constructionPlaneHandleFixture()
    let service = ViewportConstructionPlaneHandleGeometry()
    let targets = service.targets(
        document: fixture.document,
        selection: fixture.selection,
        layout: fixture.layout
    )
    let originTarget = try #require(targets.first { $0.handle == .origin })
    let normalTarget = try #require(targets.first { $0.handle == .normal })

    let originHit = try #require(service.target(
        at: originTarget.projectedOrigin,
        document: fixture.document,
        selection: fixture.selection,
        layout: fixture.layout
    ))
    let normalHit = try #require(service.target(
        at: normalTarget.projectedNormalEnd,
        document: fixture.document,
        selection: fixture.selection,
        layout: fixture.layout
    ))

    #expect(originHit.identity == originTarget.identity)
    #expect(normalHit.identity == normalTarget.identity)
}

@Test func constructionPlaneOriginDragMovesOriginAndPreservesNormal() throws {
    let fixture = try constructionPlaneHandleFixture()
    let originTarget = try #require(ViewportConstructionPlaneHandleGeometry().targets(
        document: fixture.document,
        selection: fixture.selection,
        layout: fixture.layout
    ).first { $0.handle == .origin })
    let start = originTarget.projectedOrigin
    let current = CGPoint(x: start.x + 32.0, y: start.y - 18.0)

    let drag = try #require(ViewportConstructionPlaneHandleGeometry().draggedTarget(
        target: originTarget,
        start: start,
        current: current,
        layout: fixture.layout
    ))

    #expect(drag.handle == .origin)
    #expect(pointDistance(drag.origin, originTarget.origin) > 1.0e-12)
    #expect(vectorDistance(drag.normal, originTarget.normal) <= 1.0e-12)
}

@Test func constructionPlaneNormalDragChangesNormalAndPreservesOrigin() throws {
    let fixture = try constructionPlaneHandleFixture()
    let normalTarget = try #require(ViewportConstructionPlaneHandleGeometry().targets(
        document: fixture.document,
        selection: fixture.selection,
        layout: fixture.layout
    ).first { $0.handle == .normal })
    let start = normalTarget.projectedNormalEnd
    let current = CGPoint(x: start.x + 26.0, y: start.y - 24.0)

    let drag = try #require(ViewportConstructionPlaneHandleGeometry().draggedTarget(
        target: normalTarget,
        start: start,
        current: current,
        layout: fixture.layout
    ))

    #expect(drag.handle == .normal)
    #expect(pointDistance(drag.origin, normalTarget.origin) <= 1.0e-12)
    #expect(vectorDistance(drag.normal, normalTarget.normal) > 1.0e-12)
    #expect(drag.normal.length > 1.0e-12)
}

private func constructionPlaneHandleFixture() throws -> (
    document: DesignDocument,
    selection: SelectionModel,
    entry: ConstructionPlaneSummaryResult.Entry,
    layout: ViewportLayout
) {
    var document = DesignDocument.empty()
    _ = try document.createConstructionPlane(
        name: "Viewport Plane",
        plane: .yz
    )
    let entry = try #require(ConstructionPlaneSummaryService().summarize(document: document).planes.first)
    let target = try #require(entry.selectionTarget())
    var selection = SelectionModel()
    try selection.selectTarget(target, in: document)
    let layout = ViewportLayout(
        modelBounds: CGRect(x: -0.25, y: -0.25, width: 0.5, height: 0.5),
        size: CGSize(width: 900.0, height: 700.0),
        basis: .axisFront(.z),
        verticalBounds: -0.25 ... 0.25
    )
    return (document, selection, entry, layout)
}

private func pointDistance(_ lhs: Point3D, _ rhs: Point3D) -> Double {
    vectorDistance(
        Vector3D(
            x: lhs.x - rhs.x,
            y: lhs.y - rhs.y,
            z: lhs.z - rhs.z
        ),
        Vector3D(x: 0.0, y: 0.0, z: 0.0)
    )
}

private func vectorDistance(_ lhs: Vector3D, _ rhs: Vector3D) -> Double {
    let dx = lhs.x - rhs.x
    let dy = lhs.y - rhs.y
    let dz = lhs.z - rhs.z
    return (dx * dx + dy * dy + dz * dz).squareRoot()
}
