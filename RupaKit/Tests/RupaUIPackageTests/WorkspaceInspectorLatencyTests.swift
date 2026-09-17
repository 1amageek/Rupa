import AppKit
import Foundation
import RupaCore
import RupaKit
import RupaProject
import Testing
@testable import RupaUI
@testable import RupaRendering

@MainActor
@Test(.serialized, .timeLimit(.minutes(1)), arguments: [false, true])
func workspaceInspectorMeasuresRealGeometryUpdateStages(includesOverlays: Bool) async throws {
    _ = NSApplication.shared
    let workspace = try DefaultProjectWorkspaceFactory().makeWorkspace()
    var current = try await workspace.evaluate()
    let planner = DefaultProjectWorkspaceActionPlanner()
    _ = try await workspace.perform(planner.source(name: "Box", commands: [
        .createExtrudedRectangle(name: "Box", plane: .xy, width: .length(0.04, .meter),
            height: .length(0.04, .meter), depth: .length(0.04, .meter), direction: .normal)
    ], from: current))
    current = try #require(workspace.view)
    let item = try #require(current.viewport.items.first)
    let nodeID = try #require(current.sceneNodeIDByOccurrenceID[item.id])
    var previous: RealityViewport?
    let clock = ContinuousClock()
    var maximumMainActorGap: Duration = .zero
    let pulse = Task { @MainActor in
        var last = clock.now
        while !Task.isCancelled {
            do { try await Task.sleep(for: .milliseconds(1)) }
            catch { return }
            let now = clock.now
            maximumMainActorGap = max(maximumMainActorGap, last.duration(to: now))
            last = now
        }
    }
    defer { pulse.cancel() }
    for index in 0..<8 {
        maximumMainActorGap = .zero
        let start = clock.now
        let commands = try WorkspaceTransformMatrix.commands(replacing: .rotationY,
            with: Double(index * 5), nodeIDs: [nodeID], in: current.document.document)
        if !commands.isEmpty {
            _ = try await workspace.perform(planner.source(name: "Rotate", commands: commands, from: current))
        }
        current = try #require(workspace.view)
        let published = clock.now
        let plan = try MeshSourcePresentationRenderPlan(scene: current.viewport)
        let planned = clock.now
        var batch: RealityViewportSpatialBatch?
        if includesOverlays {
            let document = current.document.document
            let ruler = current.workspaceState.ruler
            let scene = ViewportSceneBuilder(objectRegistry: current.objectRegistry).build(
                document: document, ruler: ruler, currentEvaluation: current.cadInteraction,
                documentGeneration: current.documentGeneration)
            let body = try #require(scene.items.first { $0.sceneNodeID == nodeID })
            let target = SelectionTarget(sceneNodeID: nodeID)
            let selection = SelectionModel(selectedTargets: [target])
            let snapshot = ViewportSpatialOverlaySemanticSnapshot(
                scene: scene,
                interaction: .init(selectedFeatureIDs: [body.featureID], selectedSceneNodeIDs: [nodeID],
                    hoveredFeatureIDs: [], hoveredSceneNodeIDs: [], selectedTargets: [target],
                    objectSelectionTargets: [target], selectedSketchEntities: [], previewSketchEntities: [],
                    hoveredSketchEntity: nil, selectedSketchRegions: [], previewSketchRegions: [], hoveredSketchRegion: nil),
                sketchCurveSource: .init(document: document, scene: scene, selection: selection, ruler: ruler),
                surfaceTransformSource: .init(document: document, scene: scene, selection: selection, ruler: ruler),
                patternSource: .init(document: document, scene: scene, selection: selection, ruler: ruler, hasRoute: true),
                editedBodies: [:], world: .init(modelBounds: body.modelBounds),
                includesGrid: true, measurement: nil, drawsLegacyBodies: false, drawsDragPreviewBodies: false)
            let builder = ViewportSpatialOverlayProducer.makeBuilder(from: snapshot, topologyRevision: UInt64(index))
            let first = try #require(plan.occurrences.first?.positions.first)
            batch = try builder(.init(x: first.x, y: first.y, z: first.z), plan.retainedByteCount).spatialBatch
        }
        let overlaid = clock.now
        let native = try await RealityViewport.prepare(plan: plan, spatialBatch: batch, reusing: previous)
        let prepared = clock.now
        #expect(plan.triangleCount > 0)
        #expect(native.snapshotID == current.viewport.snapshotID)
        print("INSPECTOR_LATENCY overlays=\(includesOverlays) \(index) workspace=\(start.duration(to: published)) plan=\(published.duration(to: planned)) overlay=\(planned.duration(to: overlaid)) native=\(overlaid.duration(to: prepared)) mainActorGap=\(maximumMainActorGap)")
        previous = native
    }
}
