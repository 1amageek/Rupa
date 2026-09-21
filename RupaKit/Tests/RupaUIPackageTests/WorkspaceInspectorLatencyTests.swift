import AppKit
import Foundation
import RupaCore
import RupaKit
import RupaProject
import Testing
import SwiftUI
@testable import RupaUI
@testable import RupaRendering

@MainActor
@Test(.timeLimit(.minutes(1)))
func workspaceCanvasMeasuresMountedPanAndPrimitiveAddition() async throws {
    _ = NSApplication.shared
    let workspace = try DefaultProjectWorkspaceFactory().makeWorkspace()
    _ = try await workspace.evaluate()
    let controller = NSHostingController(rootView: MainView(workspace: workspace,
        operationSequencer: ProjectWorkspaceOperationSequencer()))
    let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1120, height: 720),
        styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentViewController = controller
    controller.view.frame = window.contentLayoutRect
    defer { window.contentViewController = nil; window.close() }
    func input(in view: NSView) -> ViewportInputSurface.InputView? {
        if let value = view as? ViewportInputSurface.InputView { return value }
        for child in view.subviews { if let value = input(in: child) { return value } }
        return nil
    }
    for _ in 0..<30 {
        controller.view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(20))
    }
    let surface = try #require(input(in: controller.view))
    let pan = try #require(surface.onPan)
    let clock = ContinuousClock()
    var durations: [Duration] = []
    for index in 0..<40 {
        let start = clock.now
        pan(CGSize(width: index.isMultiple(of: 2) ? 3 : -3, height: 1), surface.bounds.size)
        controller.view.layoutSubtreeIfNeeded()
        durations.append(start.duration(to: clock.now))
        try await Task.sleep(for: .milliseconds(16))
    }
    durations.sort()
    print("CANVAS_PAN median=\(durations[20]) p95=\(durations[38]) max=\(durations[39])")
    let zoom = try #require(surface.onZoom)
    durations.removeAll(keepingCapacity: true)
    for index in 0..<40 {
        let start = clock.now
        zoom(index.isMultiple(of: 2) ? 1.01 : 1 / 1.01,
             CGPoint(x: surface.bounds.midX, y: surface.bounds.midY), surface.bounds.size)
        controller.view.layoutSubtreeIfNeeded()
        durations.append(start.duration(to: clock.now))
        try await Task.sleep(for: .milliseconds(16))
    }
    durations.sort()
    print("CANVAS_ZOOM median=\(durations[20]) p95=\(durations[38]) max=\(durations[39])")
    let planner = DefaultProjectWorkspaceActionPlanner()
    var previous: RealityViewport?
    for shape in WorkspaceSolidShape.allCases {
        let current = try #require(workspace.view)
        let commandPlanner = WorkspaceCanvasCommandPlanner(context: .init(
            document: current.document.document, selection: current.selection,
            workspaceState: current.workspaceState, objectRegistry: current.objectRegistry,
            polygonState: .standard, sketchInputState: .init()), solidShape: shape)
        let start = clock.now
        let command = try #require(try commandPlanner.clickCommand(tool: .solid, targetSceneNodeID: nil,
            modelPoint: .init(x: 0, y: 0), modelWorldPoint: nil, sketchPlane: .xy, placementCellMeters: 0.04))
        _ = try await workspace.perform(planner.source(name: shape.rawValue, commands: [command], from: current))
        let evaluated = clock.now
        let updated = try #require(workspace.view)
        let plan = try MeshSourcePresentationRenderPlan(scene: updated.viewport)
        let planned = clock.now
        previous = try await RealityViewport.prepare(plan: plan, spatialBatch: nil, reusing: previous)
        print("CANVAS_ADD shape=\(shape.rawValue) evaluation=\(start.duration(to: evaluated)) plan=\(evaluated.duration(to: planned)) native=\(planned.duration(to: clock.now))")
        #expect(updated.viewport.items.count > current.viewport.items.count)
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func workspaceInspectorMeasuresRealGeometryUpdateStages() async throws {
    for includesOverlays in [false, true] {
        try await measureGeometryUpdateStages(includesOverlays: includesOverlays)
    }
}

@MainActor
private func measureGeometryUpdateStages(includesOverlays: Bool) async throws {
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
