import CoreGraphics
import RupaCore
import RupaViewportScene
import Testing
@testable import RupaRendering

@Test func constructionPlaneHandleGeometryBuildsSelectedPlaneHandles() throws {
    let fixture = try constructionPlaneHandleFixture()
    let targets = ViewportConstructionPlaneHandleGeometry().targets(
        document: fixture.document,
        ruler: fixture.ruler,
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

private func constructionPlaneHandleFixture() throws -> (
    document: DesignDocument,
    ruler: RulerConfiguration,
    selection: SelectionModel,
    entry: ConstructionPlaneSummaryResult.Entry,
    layout: ViewportLayout
) {
    var document = DesignDocument.empty()
    let planeID = try document.createConstructionPlane(
        name: "Viewport Plane",
        plane: .yz
    )
    let entry = try #require(ConstructionPlaneSummaryService().summarize(
        document: document,
        activePlaneID: planeID
    ).planes.first)
    let target = try #require(entry.selectionTarget())
    var selection = SelectionModel()
    try selection.selectTarget(target, in: document)
    let layout = ViewportLayout(
        modelBounds: CGRect(x: -0.25, y: -0.25, width: 0.5, height: 0.5),
        size: CGSize(width: 900.0, height: 700.0),
        basis: .axisFront(.z),
        verticalBounds: -0.25 ... 0.25
    )
    return (
        document,
        .standard(for: .millimeter),
        selection,
        entry,
        layout
    )
}
