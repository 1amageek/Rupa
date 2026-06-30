import CoreGraphics
import RupaCore
import RupaViewportScene
import SwiftCAD
import Testing
@testable import RupaRendering

@MainActor
@Test func viewportBridgeCurveEndpointAffordanceServiceProjectsSelectedBridgeEndpoints() throws {
    let fixture = try bridgeCurveEndpointAffordanceFixture()

    let candidates = try ViewportBridgeCurveEndpointAffordanceService().candidates(
        document: fixture.document,
        scene: fixture.scene,
        selection: SelectionModel(selectedTargets: [fixture.bridgeSelectionTarget]),
        layout: fixture.layout
    )

    let item = try #require(fixture.scene.items.first { $0.featureID == fixture.featureID })
    let expectedFirst = fixture.layout.project(CGPoint(x: 0.003, y: 0.0), in: item)
    let expectedSecond = fixture.layout.project(CGPoint(x: 0.006, y: 0.003), in: item)
    let first = try #require(candidates.first { $0.target.role == .first })
    let second = try #require(candidates.first { $0.target.role == .second })

    #expect(candidates.count == 2)
    #expect(first.target.sourceID == fixture.sourceID)
    #expect(second.target.sourceID == fixture.sourceID)
    #expect(first.target.bridgeEntityID == fixture.bridgeID)
    #expect(second.target.bridgeEntityID == fixture.bridgeID)
    #expect(abs(first.projectedPoint.x - expectedFirst.x) < 1.0e-9)
    #expect(abs(first.projectedPoint.y - expectedFirst.y) < 1.0e-9)
    #expect(abs(second.projectedPoint.x - expectedSecond.x) < 1.0e-9)
    #expect(abs(second.projectedPoint.y - expectedSecond.y) < 1.0e-9)
    #expect(first.projectedTangentTip != first.projectedPoint)
    #expect(second.projectedTangentTip != second.projectedPoint)
}

@MainActor
@Test func viewportBridgeCurveEndpointAffordanceServiceHitTestsNearestEndpointHandle() throws {
    let fixture = try bridgeCurveEndpointAffordanceFixture()
    let service = ViewportBridgeCurveEndpointAffordanceService()
    let candidates = try service.candidates(
        document: fixture.document,
        scene: fixture.scene,
        selection: SelectionModel(selectedTargets: [fixture.bridgeSelectionTarget]),
        layout: fixture.layout
    )
    let first = try #require(candidates.first { $0.target.role == .first })
    let second = try #require(candidates.first { $0.target.role == .second })

    let firstHit = service.target(
        at: CGPoint(x: first.projectedPoint.x + 2.0, y: first.projectedPoint.y + 1.0),
        candidates: candidates
    )
    let secondHit = service.target(
        at: CGPoint(x: second.projectedPoint.x - 1.0, y: second.projectedPoint.y - 2.0),
        candidates: candidates
    )
    let missedHit = service.target(
        at: CGPoint(x: first.projectedPoint.x + 100.0, y: first.projectedPoint.y + 100.0),
        candidates: candidates
    )

    #expect(firstHit?.identity == first.target.identity)
    #expect(secondHit?.identity == second.target.identity)
    #expect(missedHit == nil)
}

@MainActor
@Test func viewportBridgeCurveEndpointAffordanceServiceIgnoresNonBridgeSelection() throws {
    let fixture = try bridgeCurveEndpointAffordanceFixture()
    let sourceLineTarget = try sourceLineSelectionTarget(
        entityID: fixture.firstLineID,
        document: fixture.document
    )

    let candidates = try ViewportBridgeCurveEndpointAffordanceService().candidates(
        document: fixture.document,
        scene: fixture.scene,
        selection: SelectionModel(selectedTargets: [sourceLineTarget]),
        layout: fixture.layout
    )

    #expect(candidates.isEmpty)
}

private struct BridgeCurveEndpointAffordanceFixture {
    var document: DesignDocument
    var scene: ViewportScene
    var layout: ViewportLayout
    var featureID: FeatureID
    var firstLineID: SketchEntityID
    var bridgeID: SketchEntityID
    var sourceID: BridgeCurveSourceID
    var bridgeSelectionTarget: SelectionTarget
}

private func bridgeCurveEndpointAffordanceFixture() throws -> BridgeCurveEndpointAffordanceFixture {
    var document = DesignDocument.empty()
    let featureID = try document.createLineSketch(
        name: "Bridge Endpoint Affordance",
        plane: .xy,
        start: bridgeCurveAffordancePoint(x: 0.0, y: 0.0),
        end: bridgeCurveAffordancePoint(x: 0.003, y: 0.0)
    )
    guard var feature = document.cadDocument.designGraph.nodes[featureID],
          case var .sketch(sketch) = feature.operation,
          let firstLineID = sketch.entities.keys.first else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Bridge endpoint affordance fixture requires a line sketch."
        )
    }
    let secondLineID = SketchEntityID()
    sketch.entities[secondLineID] = .line(
        SketchLine(
            start: bridgeCurveAffordancePoint(x: 0.006, y: 0.003),
            end: bridgeCurveAffordancePoint(x: 0.006, y: 0.006)
        )
    )
    feature.operation = .sketch(sketch)
    document.cadDocument.designGraph.nodes[featureID] = feature
    document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()

    let bridgeID = try document.createBridgeCurve(
        featureID: featureID,
        firstEndpoint: BridgeCurveEndpoint(reference: .lineEnd(firstLineID)),
        secondEndpoint: BridgeCurveEndpoint(reference: .lineStart(secondLineID)),
        continuity: .g1
    )
    let source = try #require(document.productMetadata.bridgeCurveSources.values.first)
    let bridgeSelectionTarget = try sourceLineSelectionTarget(
        entityID: bridgeID,
        document: document
    )
    let scene = ViewportSceneBuilder().build(document: document)
    let layout = try #require(ViewportLayout(
        scene: scene,
        size: CGSize(width: 900.0, height: 700.0)
    ))
    return BridgeCurveEndpointAffordanceFixture(
        document: document,
        scene: scene,
        layout: layout,
        featureID: featureID,
        firstLineID: firstLineID,
        bridgeID: bridgeID,
        sourceID: source.id,
        bridgeSelectionTarget: bridgeSelectionTarget
    )
}

private func sourceLineSelectionTarget(
    entityID: SketchEntityID,
    document: DesignDocument
) throws -> SelectionTarget {
    let summary = try SketchEntitySummaryService().summarize(document: document)
    let entry = try #require(summary.entries.first { $0.entityID == entityID.description })
    return try #require(entry.selectionTarget())
}

private func bridgeCurveAffordancePoint(x: Double, y: Double) -> SketchPoint {
    SketchPoint(
        x: .length(x, .meter),
        y: .length(y, .meter)
    )
}
