import AppKit
import CoreGraphics
import Foundation
import Metal
import RupaCore
import RupaCoreTypes
import RupaGeometry
import RupaProjectModel
import RupaViewportScene
import SwiftCAD
import Testing
@testable import RupaRendering

@MainActor
@Test(.timeLimit(.minutes(1)))
func viewportSurfaceViewPreservesInputAcrossFailureAndClearsOnSuccess() async throws {
    let scene = try surfaceLifecycleScene()
    let plan = try MeshSourcePresentationRenderPlan(scene: scene)
    let renderer = try ViewportSurfaceRenderer(plan: plan)
    let layout = surfaceLifecycleLayout()
    var results: [MeshSourcePresentationRenderError?] = []
    let input = surfaceLifecycleInput(renderer: renderer, layout: layout) { result in
        results.append(result)
    }
    let view = ViewportSurfaceView.SurfaceView(frame: .zero, device: renderer.device)
    view.input = input

    var oversizedError: MeshSourcePresentationRenderError?
    do {
        _ = try ViewportSurfaceRenderer.attachmentByteCount(width: 20_000, height: 20_000)
    } catch let error as MeshSourcePresentationRenderError {
        oversizedError = error
    }
    let oversized = try #require(oversizedError)
    #expect(oversized.code == .resourceExhausted)

    view.reportDrawResult(error: oversized, for: renderer)
    #expect(results.count == 1)
    #expect(results[0]?.code == .resourceExhausted)
    #expect(view.input?.renderer === renderer)

    let commandCompleted = try await encodeSurfaceLifecycleFrame(renderer, layout: layout)
    #expect(commandCompleted)
    view.reportDrawResult(error: nil, for: renderer)
    #expect(results.count == 2)
    #expect(results[1] == nil)
    #expect(view.input?.renderer === renderer)

    let replacementRenderer = try ViewportSurfaceRenderer(plan: plan)
    view.input = surfaceLifecycleInput(renderer: replacementRenderer, layout: layout) { result in
        results.append(result)
    }
    let resultCountBeforeStaleReport = results.count
    view.reportDrawResult(error: oversized, for: renderer)
    #expect(results.count == resultCountBeforeStaleReport)
    #expect(view.input?.renderer === replacementRenderer)

    view.reportDrawResult(error: oversized, for: replacementRenderer)
    #expect(results.count == resultCountBeforeStaleReport + 1)
    let lastResult = results.last ?? nil
    #expect(lastResult?.code == .resourceExhausted)
}

@MainActor
private func surfaceLifecycleInput(
    renderer: ViewportSurfaceRenderer,
    layout: ViewportLayout,
    onDrawResult: @escaping (MeshSourcePresentationRenderError?) -> Void
) -> ViewportSurfaceView {
    ViewportSurfaceView(
        renderer: renderer,
        layout: layout,
        interaction: MeshSourcePresentationInteractionStateResolver(
            sceneNodeIDByOccurrenceID: [:],
            selectedSceneNodeIDs: [],
            previewSceneNodeIDs: [],
            hoveredSceneNodeID: nil
        ),
        sectionPlane: nil,
        retainedSide: .front,
        sectionTolerance: 0,
        onDrawResult: onDrawResult
    )
}

private func surfaceLifecycleScene() throws -> UniversalViewportScene {
    var builder = MeshSourceBuilder(identity: "mesh.surface-lifecycle")
    try builder.reserveCapacity(vertexCount: 4, faceCount: 1, cornerCount: 4)
    let first = try builder.addVertex(GeometryPoint3D(x: 0, y: 0, z: 0))
    let second = try builder.addVertex(GeometryPoint3D(x: 1, y: 0, z: 0))
    let third = try builder.addVertex(GeometryPoint3D(x: 1, y: 1, z: 0))
    let fourth = try builder.addVertex(GeometryPoint3D(x: 0, y: 1, z: 0))
    _ = try builder.addFace(vertexIDs: [first, second, third, fourth])
    let source = try builder.build()
    let projectID = ProjectID(rawValue: "project.surface-lifecycle")
    let occurrenceID = SceneOccurrenceID(rawValue: "occurrence.surface-lifecycle")
    let definitionID = ObjectDefinitionID(rawValue: "definition.surface-lifecycle")
    let representationID = GeometryRepresentationID(rawValue: "representation.surface-lifecycle")
    let transform = GeometryTransform3D.identity
    let item = UniversalViewportSceneItem(
        id: occurrenceID,
        definitionID: definitionID,
        displayName: "Surface lifecycle",
        representationID: representationID,
        reference: .authoredMesh(source.identity),
        mesh: source,
        worldTransform: transform,
        worldBounds: try source.bounds().transformed(by: transform)
    )
    return UniversalViewportScene(
        snapshotID: EvaluationSnapshotID(
            projectID: projectID,
            purpose: .presentation,
            sourceRevision: DocumentTransactionRevision()
        ),
        projectID: projectID,
        items: [item]
    )
}

private func surfaceLifecycleLayout() -> ViewportLayout {
    ViewportLayout(
        modelBounds: CGRect(x: 0, y: 0, width: 1, height: 1),
        size: CGSize(width: 64, height: 64),
        basis: ViewportProjectionBasis(
            mode: .orbit,
            xDirection: CGVector(dx: 1, dy: 0),
            yDirection: CGVector(dx: 0, dy: -1),
            zDirection: .zero
        ),
        verticalBounds: -1 ... 1
    )
}

@MainActor
private func encodeSurfaceLifecycleFrame(
    _ renderer: ViewportSurfaceRenderer,
    layout: ViewportLayout
) async throws -> Bool {
    let colorDescriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .bgra8Unorm, width: 64, height: 64, mipmapped: false
    )
    colorDescriptor.usage = [.renderTarget]
    colorDescriptor.storageMode = .shared
    let color = try #require(renderer.device.makeTexture(descriptor: colorDescriptor))
    let depthDescriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .depth32Float, width: 64, height: 64, mipmapped: false
    )
    depthDescriptor.usage = [.renderTarget]
    depthDescriptor.storageMode = .private
    let depth = try #require(renderer.device.makeTexture(descriptor: depthDescriptor))
    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = color
    pass.colorAttachments[0].loadAction = .clear
    pass.colorAttachments[0].storeAction = .store
    pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
    pass.depthAttachment.texture = depth
    pass.depthAttachment.loadAction = .clear
    pass.depthAttachment.storeAction = .dontCare
    pass.depthAttachment.clearDepth = 1

    let command = try renderer.makeCommandBuffer()
    try renderer.encode(into: command, pass: pass, layout: layout)
    await withCheckedContinuation { continuation in
        command.addCompletedHandler { _ in continuation.resume() }
        command.commit()
    }
    return command.status == .completed
}
