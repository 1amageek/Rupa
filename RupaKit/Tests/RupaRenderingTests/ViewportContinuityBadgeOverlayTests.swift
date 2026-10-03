import CoreGraphics
import RupaCore
import RupaViewportScene
import SwiftCAD
import Testing
@testable import RupaRendering

/// Continuity badges: a label at the middle of each boundary edge, clickable as an affordance whose
/// action reports that edge; a boundary the drawn scene lacks draws none.
@MainActor
@Test(.timeLimit(.minutes(1)))
func continuityBadgesLabelEachEdgeAtItsMiddleAndReportItOnClick() throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let featureID = try #require(session.document.cadDocument.designGraph.order.last)
    let scene = ViewportSceneBuilder().build(document: session.document, ruler: .standard(for: .meter), evaluationPolicy: .evaluateOnDemand)
    let item = try #require(scene.items.first { if case .body = $0.kind { return $0.featureID == featureID } else { return false } })
    guard case .body(let component) = item.kind, let topology = component.topology else {
        Issue.record("The extrude item has no body topology.")
        return
    }
    let nodeID = try #require(item.sceneNodeID)
    let edges = Array(topology.edges.prefix(2))
    #expect(edges.count == 2)
    let targets = edges.map { SelectionTarget(sceneNodeID: nodeID, component: .edge($0.componentID)) }
    let missing = SelectionTarget(sceneNodeID: SceneNodeID(), component: .edge(edges[0].componentID))
    var snapshot = ViewportSpatialOverlaySemanticSnapshot(
        scene: scene,
        interaction: .init(
            selectedFeatureIDs: [], selectedSceneNodeIDs: [], hoveredFeatureIDs: [], hoveredSceneNodeIDs: [],
            selectedTargets: [], selectedSketchEntities: [], previewSketchEntities: [], hoveredSketchEntity: nil,
            selectedSketchRegions: [], previewSketchRegions: [], hoveredSketchRegion: nil
        ),
        editedBodies: [:],
        world: .init(modelBounds: item.modelBounds),
        measurement: nil,
        drawsLegacyBodies: false,
        drawsDragPreviewBodies: false
    )
    snapshot.continuityBadges = [
        ViewportContinuityBadge(target: targets[0], label: "G1"),
        ViewportContinuityBadge(target: targets[1], label: "G2"),
        ViewportContinuityBadge(target: missing, label: "G0"),
    ]
    var labels: [ViewportSpatialOverlayInput.Label] = []
    var markers: [ViewportSpatialOverlayInput.Marker] = []
    var records: [ViewportSpatialInteractionRecord] = []
    var families: Set<ViewportSpatialOverlayFamily> = []
    try ViewportSpatialOverlayProducer.appendContinuityBadges(
        snapshot, labels: &labels, markers: &markers, interactionRecords: &records, activeFamilies: &families
    )
    #expect(labels.map(\.value.text) == ["G1", "G2"])
    #expect(markers.count == 2)
    #expect(records.count == 2)
    for (index, (edge, target)) in zip(edges, targets).enumerated() {
        let label = labels[index].value
        let middle = try #require(ViewportSpatialOverlayProducer.midpoint(of: edge.displayPoints))
        #expect(label.anchor == item.modelTransform.point(middle))
        #expect(label.hitRectPoints != nil)
        let handle = try #require(label.handleIndex)
        #expect(records[Int(handle)].identity == .affordance(ViewportAffordanceTarget(
            featureID: featureID, selectionTarget: target, action: .continuityBadge(target)
        )))
    }
}
