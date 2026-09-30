import AppKit
import Foundation
import RupaCore
import RupaKit
import RupaProject
import Testing
@testable import RupaUI
@testable import RupaRendering

/// A hover-only change is a small delta against the mounted overlay, and the mounted items it
/// keeps together with the items it adds are exactly the complete overlay.
@MainActor
@Suite struct ViewportSpatialDeltaTests {
    private struct Scenario {
        let document: DesignDocument
        let scene: ViewportScene
        let body: ViewportSceneItem
        let nodeID: SceneNodeID
        let edges: [SelectionTarget]
        let origin: Point3D
        let retainedSurfaceByteCount: Int
        let ruler: RulerConfiguration
    }

    private func scenario() async throws -> Scenario {
        let workspace = try DefaultProjectWorkspaceFactory().makeWorkspace()
        var current = try await workspace.evaluate()
        let planner = DefaultProjectWorkspaceActionPlanner()
        let commands: [EditorCommand] = (0..<4).map { index in
            .createExtrudedRectangle(name: "Box \(index)", plane: .xy, width: .length(0.04, .meter),
                height: .length(0.04, .meter), depth: .length(0.04, .meter), direction: .normal)
        }
        _ = try await workspace.perform(planner.source(name: "Boxes", commands: commands, from: current))
        current = try #require(workspace.view)
        let document = current.document.document
        let scene = ViewportSceneBuilder(objectRegistry: current.objectRegistry).build(
            document: document, ruler: current.workspaceState.ruler, currentEvaluation: current.cadInteraction,
            documentGeneration: current.documentGeneration)
        let body = try #require(scene.items.first { $0.sceneNodeID != nil })
        let nodeID = try #require(body.sceneNodeID)
        let edges = try TopologySnapshotService().snapshot(
            document: document, currentEvaluation: current.cadInteraction, currentGeneration: current.documentGeneration
        ).entries.filter { $0.kind == .edge && $0.sceneNodeID == nodeID.description }.compactMap { $0.selectionTarget() }
        let plan = try MeshSourcePresentationRenderPlan(scene: current.viewport)
        let first = try #require(plan.occurrences.first?.positions.first)
        return Scenario(document: document, scene: scene, body: body, nodeID: nodeID, edges: edges,
            origin: Point3D(x: first.x, y: first.y, z: first.z), retainedSurfaceByteCount: plan.retainedByteCount,
            ruler: current.workspaceState.ruler)
    }

    private func overlay(_ scenario: Scenario, hovered: SelectionTarget?) throws -> ViewportSpatialOverlayProducer.Output {
        let selection = SelectionModel(selectedTargets: [SelectionTarget(sceneNodeID: scenario.nodeID)], hoveredTarget: hovered)
        let targets = selection.selectedTargets
        let snapshot = ViewportSpatialOverlaySemanticSnapshot(
            scene: scenario.scene,
            interaction: .init(selectedFeatureIDs: [scenario.body.featureID], selectedSceneNodeIDs: [scenario.nodeID],
                hoveredFeatureIDs: [], hoveredSceneNodeIDs: [], selectedTargets: targets,
                objectSelectionTargets: targets, hoveredTarget: hovered, selectedSketchEntities: [],
                previewSketchEntities: [], hoveredSketchEntity: nil, selectedSketchRegions: [],
                previewSketchRegions: [], hoveredSketchRegion: nil),
            sketchCurveSource: .init(document: scenario.document, scene: scenario.scene, selection: selection, ruler: scenario.ruler),
            surfaceTransformSource: .init(document: scenario.document, scene: scenario.scene, selection: selection, ruler: scenario.ruler),
            patternSource: .init(document: scenario.document, scene: scenario.scene, selection: selection, ruler: scenario.ruler, hasRoute: true),
            editedBodies: [:], world: .init(modelBounds: scenario.body.modelBounds),
            includesGrid: true, measurement: nil, drawsLegacyBodies: false, drawsDragPreviewBodies: false)
        return try ViewportSpatialOverlayProducer.makeBuilder(from: snapshot, topologyRevision: 1)(
            scenario.origin, scenario.retainedSurfaceByteCount)
    }

    /// The items drawn once `delta` applies to `mounted`: every unsuppressed mounted item, its
    /// handle named by identity, and every added item.
    private func drawn(
        _ mounted: ViewportSpatialOverlayProducer.Output, _ delta: RealityViewportSpatialDelta
    ) -> [String] {
        func handle(_ index: UInt32?, _ records: [ViewportSpatialInteractionRecord]) -> String {
            index.map { "\(records[Int($0)].identity)" } ?? "-"
        }
        func describe(_ batch: RealityViewportSpatialBatch, records: [ViewportSpatialInteractionRecord],
                      skip: RealityViewportSpatialDelta.Suppression?) -> [String] {
            var result: [String] = []
            for (index, var item) in batch.meshes.enumerated() where skip?.meshes.contains(index) != true {
                let h = handle(item.handleIndex, records); item.handleIndex = nil; result.append("mesh \(item) \(h)")
            }
            for (index, var item) in batch.paths.enumerated() where skip?.paths.contains(index) != true {
                let h = handle(item.handleIndex, records); item.handleIndex = nil; result.append("path \(item) \(h)")
            }
            for (index, var item) in batch.labels.enumerated() where skip?.labels.contains(index) != true {
                let h = handle(item.handleIndex, records); item.handleIndex = nil; result.append("label \(item) \(h)")
            }
            for (index, var item) in batch.markers.enumerated() where skip?.markers.contains(index) != true {
                let h = handle(item.handleIndex, records); item.handleIndex = nil; result.append("marker \(item) \(h)")
            }
            for (index, var item) in batch.cameraLines.enumerated() where skip?.cameraLines.contains(index) != true {
                let h = handle(item.handleIndex, records); item.handleIndex = nil; result.append("line \(item) \(h)")
            }
            for (index, var item) in batch.cameraPaths.enumerated() where skip?.cameraPaths.contains(index) != true {
                let h = handle(item.handleIndex, records); item.handleIndex = nil; result.append("cpath \(item) \(h)")
            }
            return result
        }
        var result = describe(mounted.spatialBatch, records: mounted.interactionRecords, skip: delta.suppressed)
        if let added = delta.added { result += describe(added, records: delta.records, skip: nil) }
        return result.sorted()
    }

    private func complete(_ output: ViewportSpatialOverlayProducer.Output) -> [String] {
        drawn(output, RealityViewportSpatialDeltaTestEmpty.delta(records: output.interactionRecords))
    }

    @Test(.timeLimit(.minutes(1)))
    func anotherHoveredEdgeIsASmallDeltaThatDrawsTheCompleteOverlay() async throws {
        let scenario = try await scenario()
        #expect(scenario.edges.count >= 2)
        let mounted = try overlay(scenario, hovered: scenario.edges[0])
        let next = try overlay(scenario, hovered: scenario.edges[1])
        let delta = try #require(try RealityViewportSpatialDelta.make(
            mounted: mounted.spatialBatch, mountedRecords: mounted.interactionRecords,
            complete: next.spatialBatch, completeRecords: next.interactionRecords))
        #expect(drawn(mounted, delta) == complete(next))
        let total = next.spatialBatch.itemCount
        #expect(delta.suppressed.count > 0)
        #expect((delta.added?.itemCount ?? 0) < total / 2)

        let unchanged = try #require(try RealityViewportSpatialDelta.make(
            mounted: next.spatialBatch, mountedRecords: next.interactionRecords,
            complete: next.spatialBatch, completeRecords: next.interactionRecords))
        #expect(unchanged.isEmpty)

        let cleared = try overlay(scenario, hovered: nil)
        let leaving = try #require(try RealityViewportSpatialDelta.make(
            mounted: next.spatialBatch, mountedRecords: next.interactionRecords,
            complete: cleared.spatialBatch, completeRecords: cleared.interactionRecords))
        #expect(drawn(next, leaving) == complete(cleared))
    }
}

/// An empty delta over a batch's own records, for describing a complete overlay.
private enum RealityViewportSpatialDeltaTestEmpty {
    static func delta(records: [ViewportSpatialInteractionRecord]) -> RealityViewportSpatialDelta {
        RealityViewportSpatialDelta(suppressed: .init(), added: nil, records: records, retainedHandles: [:])
    }
}
