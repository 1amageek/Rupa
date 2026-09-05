import Foundation
import CoreGraphics
import Metal
import Synchronization
import RupaCore
import RupaCoreTypes
import RupaEvaluation
import RupaProjectModel
import RupaViewportScene
import Testing
@testable import RupaRendering
@testable import RupaGeometry

@Test(.timeLimit(.minutes(1)))
func presentationPlanBoundaryIndicesExcludeTriangulationDiagonals() throws {
    let (scene, _) = try presentationScene(
        references: [.authoredMesh(GeometrySourceID(rawValue: "mesh.presentation"))],
        transforms: [.identity]
    )
    let plan = try MeshSourcePresentationRenderPlan(scene: scene)
    let occurrence = try #require(plan.occurrences.first)

    #expect(plan.triangleCount == 2)
    #expect(plan.boundaryIndexCount == 8)
    #expect(occurrence.boundaryIndexCount == 8)
    #expect(occurrence.boundaryCornerIndices.filter { $0 == UInt32.max }.count == 2)
}

@Test(.timeLimit(.minutes(1)))
func presentationPlanBoundaryAdmissionChargesSixIndicesAndCombinedPages() throws {
    let triangleSource = try presentationTriangleSource()
    let (triangleScene, _) = try presentationScene(
        source: triangleSource,
        references: [.authoredMesh(triangleSource.identity)],
        transforms: [.identity]
    )
    let trianglePlan = try MeshSourcePresentationRenderPlan(scene: triangleScene)
    #expect(trianglePlan.triangleCount == 1)
    #expect(trianglePlan.boundaryIndexCount == 6)

    let pointSource = try presentationPointCloudSource()
    let (pointScene, _) = try presentationScene(
        source: pointSource,
        references: [.authoredMesh(pointSource.identity)],
        transforms: [.identity]
    )
    let pointPlan = try MeshSourcePresentationRenderPlan(scene: pointScene)
    let expectedTriangleAndBoundaryBytes =
        3 * 3 * MemoryLayout<UInt32>.stride
        + MemoryLayout<MeshFaceID>.stride
        + 6 * MemoryLayout<UInt32>.stride
    #expect(
        trianglePlan.retainedByteCount - pointPlan.retainedByteCount
            == expectedTriangleAndBoundaryBytes
    )

    let expectedPositionBytes = 3 * (
        MemoryLayout<GeometryPoint3D>.stride
            + MemoryLayout<MeshVertexID>.stride
            + 16
    )
    let expectedCombinedPageBytes = 64 * 1024
    let expectedItemBytes =
        MemoryLayout<MeshSourcePresentationRenderPlan.Occurrence>.stride + 128
    let emptyScene = UniversalViewportScene(
        snapshotID: pointScene.snapshotID,
        projectID: pointScene.projectID,
        items: [],
        copyTelemetry: pointScene.copyTelemetry
    )
    let emptyPlan = try MeshSourcePresentationRenderPlan(scene: emptyScene)
    #expect(
        pointPlan.retainedByteCount - emptyPlan.retainedByteCount
            == expectedItemBytes + expectedCombinedPageBytes + expectedPositionBytes
    )

    let limits = MeshSourcePresentationPlanLimits(
        maxItemCount: MeshSourcePresentationPlanLimits.standard.maxItemCount,
        maxPositionCount: MeshSourcePresentationPlanLimits.standard.maxPositionCount,
        maxTriangleCount: MeshSourcePresentationPlanLimits.standard.maxTriangleCount,
        // Every retained byte except the admitted boundary output fits; the
        // checked boundary charge must reject before any storage is grown.
        maxRetainedByteCount: trianglePlan.retainedByteCount - 1
    )
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try MeshSourcePresentationRenderPlan(scene: triangleScene, planLimits: limits)
    }
}

@Test(.timeLimit(.minutes(1)))
func presentationPlanMemoryCeilingIncludesScratchAndGPUStorage() throws {
    #expect(MeshSourcePresentationPlanLimits.hardMaximum.maxRetainedByteCount <= (8 * 1024 * 1024 * 1024) / 40)
    let (scene, _) = try presentationScene(
        references: [.authoredMesh(GeometrySourceID(rawValue: "mesh.presentation"))], transforms: [.identity]
    )
    let plan = try MeshSourcePresentationRenderPlan(scene: scene)
    #expect(plan.workingByteCount > plan.retainedByteCount)
    let limits = MeshSourcePresentationPlanLimits(
        maxItemCount: 1, maxPositionCount: 4, maxTriangleCount: 2,
        maxRetainedByteCount: plan.workingByteCount - 1
    )
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try MeshSourcePresentationRenderPlan(scene: scene, planLimits: limits)
    }
    #expect(throws: MeshTriangulationError.self) {
        try MeshSourceTriangulationIndex.storageReservation(vertexCount: Int.max)
    }
}

@Test(.timeLimit(.minutes(1)))
func viewportSurfaceGPUUsesDepthInsteadOfSelectionDrawOrder() async throws {
    let reference = GeometrySourceReference.authoredMesh(GeometrySourceID(rawValue: "mesh.presentation"))
    for frontIndex in 0...1 {
        let transforms = try (0...1).map { index in
            try translationTransform(x: -0.5, y: -0.5, z: index == frontIndex ? 0.3 : -0.3)
        }
        let (scene, _) = try presentationScene(references: [reference, reference], transforms: transforms)
        let plan = try MeshSourcePresentationRenderPlan(scene: scene)
        let renderer = try ViewportSurfaceRenderer(plan: plan)
        let frontID = SceneOccurrenceID(rawValue: "occurrence.presentation-render.\(frontIndex)")
        let layout = surfaceTestLayout()
        #expect(MeshSourcePresentationScreenHitTester().occurrenceID(
            at: CGPoint(x: 64, y: 64), in: plan, layout: layout
        ) == frontID)
        for displayMode in ViewportDisplayMode.allCases {
            let pixels = try await surfacePixels(
                renderer,
                layout: layout,
                displayMode: displayMode,
                selected: frontID
            )
            let pixel = surfacePixel(pixels, x: 64, y: 64)
            switch displayMode {
            case .solid, .solidWithEdges:
                #expect(pixel.alpha == 255)
                #expect(Int(pixel.blue) > Int(pixel.red) * 2)
            case .wireframe:
                #expect(pixel.alpha == 0)
            case .normals:
                #expect(pixel.alpha == 255)
                #expect(abs(Int(pixel.red) - 128) <= 8)
                #expect(abs(Int(pixel.green) - 128) <= 8)
                #expect(abs(Int(pixel.blue) - 255) <= 8)
            }
        }
    }
}

@Test(.timeLimit(.minutes(1)))
func viewportSurfaceGPUKeepsTheFirstOccurrenceAtEqualDepthLikePicking() async throws {
    let reference = GeometrySourceReference.authoredMesh(GeometrySourceID(rawValue: "mesh.presentation"))
    let transform = try translationTransform(x: -0.5, y: -0.5, z: 0)
    let (original, _) = try presentationScene(references: [reference, reference], transforms: [transform, transform])
    for items in [original.items, Array(original.items.reversed())] {
        let scene = UniversalViewportScene(
            snapshotID: original.snapshotID, projectID: original.projectID,
            items: items, copyTelemetry: original.copyTelemetry
        )
        let plan = try MeshSourcePresentationRenderPlan(scene: scene)
        let layout = surfaceTestLayout()
        let picked = try #require(MeshSourcePresentationScreenHitTester().occurrenceID(
            at: CGPoint(x: 64, y: 64), in: plan, layout: layout
        ))
        #expect(picked == items[0].id)
        let pixels = try await surfacePixels(ViewportSurfaceRenderer(plan: plan), layout: layout, selected: picked)
        let pixel = surfacePixel(pixels, x: 64, y: 64)
        #expect(Int(pixel.blue) > Int(pixel.red) * 2)
    }
}

@Test(.timeLimit(.minutes(1)))
func viewportSurfaceGPUShowsFaceLightingAndSupportsConcurrentReadOnlyGeometry() async throws {
    var builder = MeshSourceBuilder(identity: GeometrySourceID(rawValue: "mesh.surface-cube"))
    let points = [
        (-0.5, -0.5, -0.5), (0.5, -0.5, -0.5), (0.5, 0.5, -0.5), (-0.5, 0.5, -0.5),
        (-0.5, -0.5, 0.5), (0.5, -0.5, 0.5), (0.5, 0.5, 0.5), (-0.5, 0.5, 0.5)
    ]
    let vertices = try points.map { try builder.addVertex(GeometryPoint3D(x: $0.0, y: $0.1, z: $0.2)) }
    for face in [[0,3,2,1], [4,5,6,7], [0,1,5,4], [3,7,6,2], [0,4,7,3], [1,2,6,5]] {
        _ = try builder.addFace(vertexIDs: face.map { vertices[$0] })
    }
    let source = try builder.build()
    let (scene, _) = try presentationScene(source: source, references: [.authoredMesh(source.identity)], transforms: [.identity])
    let plan = try MeshSourcePresentationRenderPlan(scene: scene)
    let renderer = try ViewportSurfaceRenderer(plan: plan)
    async let first = surfacePixels(renderer, layout: surfaceTestLayout(basis: .isometric))
    async let second = surfacePixels(renderer, layout: surfaceTestLayout(basis: .isometric))
    let (pixels, repeated) = try await (first, second)
    #expect(pixels == repeated)
    var darkest = 255
    var lightest = 0
    var filled = 0
    for offset in stride(from: 0, to: pixels.count, by: 4) where pixels[offset + 3] == 255 {
        darkest = min(darkest, Int(pixels[offset + 1]))
        lightest = max(lightest, Int(pixels[offset + 1]))
        filled += 1
    }
    #expect(filled > 1_000)
    #expect(lightest - darkest > 35)
    #expect(renderer.allocatedGeometryByteCount <= plan.retainedByteCount)
}

@Test(.timeLimit(.minutes(1)))
func viewportSurfaceGPUSolidWithEdgesAddsSourceFaceBoundaries() async throws {
    let (scene, _) = try presentationScene(
        references: [.authoredMesh(GeometrySourceID(rawValue: "mesh.presentation"))],
        transforms: [translationTransform(x: -0.5, y: -0.5, z: 0)]
    )
    let plan = try MeshSourcePresentationRenderPlan(scene: scene)
    let renderer = try ViewportSurfaceRenderer(plan: plan)
    let layout = surfaceTestLayout()
    let solid = try await surfacePixels(renderer, layout: layout, displayMode: .solid)
    let withEdges = try await surfacePixels(renderer, layout: layout, displayMode: .solidWithEdges)

    var changedPixelCount = 0
    for offset in stride(from: 0, to: solid.count, by: 4) {
        let differs = (0..<4).contains { channel in
            abs(Int(solid[offset + channel]) - Int(withEdges[offset + channel])) > 8
        }
        if differs {
            changedPixelCount += 1
        }
    }
    #expect(changedPixelCount > 0)
}

@Test(.timeLimit(.minutes(1)))
func viewportSurfaceGPUWireframeOmitsTheQuadTriangulationDiagonal() async throws {
    let (scene, _) = try presentationScene(
        references: [.authoredMesh(GeometrySourceID(rawValue: "mesh.presentation"))],
        transforms: [translationTransform(x: -0.5, y: -0.5, z: 0)]
    )
    let plan = try MeshSourcePresentationRenderPlan(scene: scene)
    let pixels = try await surfacePixels(
        ViewportSurfaceRenderer(plan: plan),
        layout: surfaceTestLayout(),
        displayMode: .wireframe
    )
    let center = surfacePixel(pixels, x: 64, y: 64)
    var boundaryPixelCount = 0
    for offset in stride(from: 0, to: pixels.count, by: 4) {
        if pixels[offset + 3] > 0 {
            boundaryPixelCount += 1
        }
    }
    #expect(boundaryPixelCount > 0)
    #expect(center.alpha == 0)
}

@Test(.timeLimit(.minutes(1)))
func viewportSurfaceGPUNormalsUseWorldSpaceRGBEncoding() async throws {
    let (scene, _) = try presentationScene(
        references: [.authoredMesh(GeometrySourceID(rawValue: "mesh.presentation"))],
        transforms: [translationTransform(x: -0.5, y: -0.5, z: 0)]
    )
    let plan = try MeshSourcePresentationRenderPlan(scene: scene)
    let pixels = try await surfacePixels(
        ViewportSurfaceRenderer(plan: plan),
        layout: surfaceTestLayout(),
        displayMode: .normals
    )
    let center = surfacePixel(pixels, x: 64, y: 64)
    #expect(center.alpha == 255)
    #expect(abs(Int(center.red) - 128) <= 8)
    #expect(abs(Int(center.green) - 128) <= 8)
    #expect(abs(Int(center.blue) - 255) <= 8)

    let reversedSource = try presentationQuadSource(reversed: true)
    let (reversedScene, _) = try presentationScene(
        source: reversedSource,
        references: [.authoredMesh(reversedSource.identity)],
        transforms: [translationTransform(x: -0.5, y: -0.5, z: 0)]
    )
    let reversedPlan = try MeshSourcePresentationRenderPlan(scene: reversedScene)
    let reversedPixels = try await surfacePixels(
        ViewportSurfaceRenderer(plan: reversedPlan),
        layout: surfaceTestLayout(),
        displayMode: .normals
    )
    let reversedCenter = surfacePixel(reversedPixels, x: 64, y: 64)
    #expect(reversedCenter.alpha == 255)
    #expect(abs(Int(reversedCenter.red) - 128) <= 8)
    #expect(abs(Int(reversedCenter.green) - 128) <= 8)
    #expect(abs(Int(reversedCenter.blue) - 0) <= 8)
}

@Test(.timeLimit(.minutes(1)))
func viewportSurfaceGPUWireframeOccludesBackBoundaryBehindFrontSurface() async throws {
    let reference = GeometrySourceReference.authoredMesh(GeometrySourceID(rawValue: "mesh.presentation"))
    let (scene, _) = try presentationScene(
        references: [reference, reference],
        transforms: [.identity, translationTransform(x: -0.5, y: -0.5, z: 0.3)]
    )
    let plan = try MeshSourcePresentationRenderPlan(scene: scene)
    let pixels = try await surfacePixels(
        ViewportSurfaceRenderer(plan: plan),
        layout: surfaceTestLayout(),
        displayMode: .wireframe
    )

    var visibleBackBoundaryPixels = 0
    for y in 8...24 {
        for x in 60...68 where surfacePixel(pixels, x: x, y: y).alpha > 0 {
            visibleBackBoundaryPixels += 1
        }
    }
    var hiddenBackBoundaryPixels = 0
    for y in 40...56 {
        for x in 60...68 where surfacePixel(pixels, x: x, y: y).alpha > 0 {
            hiddenBackBoundaryPixels += 1
        }
    }
    #expect(visibleBackBoundaryPixels > 0)
    #expect(hiddenBackBoundaryPixels == 0)
}

@Test(.timeLimit(.minutes(1)))
func viewportSurfaceGPUWireframeKeepsFirstOccurrenceAtEqualDepthForBoundaryLines() async throws {
    let reference = GeometrySourceReference.authoredMesh(GeometrySourceID(rawValue: "mesh.presentation"))
    let centered = try translationTransform(x: -0.5, y: -0.5, z: 0)
    let (scene, _) = try presentationScene(
        references: [reference, reference],
        transforms: [centered, centered]
    )
    let plan = try MeshSourcePresentationRenderPlan(scene: scene)
    let layout = surfaceTestLayout()
    let firstID = SceneOccurrenceID(rawValue: "occurrence.presentation-render.0")
    let secondID = SceneOccurrenceID(rawValue: "occurrence.presentation-render.1")
    let firstSelected = try await surfacePixels(
        ViewportSurfaceRenderer(plan: plan),
        layout: layout,
        displayMode: .wireframe,
        selected: firstID
    )
    let secondSelected = try await surfacePixels(
        ViewportSurfaceRenderer(plan: plan),
        layout: layout,
        displayMode: .wireframe,
        selected: secondID
    )

    var selectedLinePixels = 0
    var firstLinePixels = 0
    for y in 30...34 {
        for x in 44...84 {
            let selectedPixel = surfacePixel(firstSelected, x: x, y: y)
            if selectedPixel.blue > 200, selectedPixel.red < 80 {
                selectedLinePixels += 1
            }
            let firstPixel = surfacePixel(secondSelected, x: x, y: y)
            if firstPixel.blue < 200, firstPixel.red > 80 {
                firstLinePixels += 1
            }
        }
    }
    #expect(selectedLinePixels > 0)
    #expect(firstLinePixels > 0)
}

@Test(.timeLimit(.minutes(1)))
func viewportSurfaceGPUSectionAgreesWithPicking() async throws {
    let reference = GeometrySourceReference.authoredMesh(GeometrySourceID(rawValue: "mesh.presentation"))
    let (scene, _) = try presentationScene(
        references: [reference], transforms: [translationTransform(x: -0.5, y: -0.5, z: 0)]
    )
    let plan = try MeshSourcePresentationRenderPlan(scene: scene)
    let renderer = try ViewportSurfaceRenderer(plan: plan)
    let plane = SectionAnalysisResult.Plane(
        sourceKind: .constructionPlane, sourceID: nil, sourceName: nil,
        origin: .origin, normal: Vector3D(x: 1, y: 0, z: 0),
        u: Vector3D(x: 0, y: 1, z: 0), v: Vector3D(x: 0, y: 0, z: 1)
    )
    let layout = surfaceTestLayout()
    let pixels = try await surfacePixels(renderer, layout: layout, section: plane)
    let resolver = MeshSourcePresentationSectionGeometryResolver(
        sectionPlan: SectionAnalysisClippingPlan(retainedSide: .front, bodies: []),
        plane: plane, toleranceMeters: 0
    )
    let picker = MeshSourcePresentationScreenHitTester()
    #expect(surfacePixel(pixels, x: 48, y: 64).alpha == 0)
    #expect(surfacePixel(pixels, x: 80, y: 64).alpha == 255)
    #expect(picker.occurrenceID(at: CGPoint(x: 48, y: 64), in: plan, layout: layout, sectionGeometryResolver: resolver) == nil)
    #expect(picker.occurrenceID(at: CGPoint(x: 80, y: 64), in: plan, layout: layout, sectionGeometryResolver: resolver) != nil)

    let wireframePixels = try await surfacePixels(
        renderer, layout: layout, displayMode: .wireframe, section: plane
    )
    var clippedBoundaryPixels = 0
    for y in 60...68 {
        for x in 28...36 where surfacePixel(wireframePixels, x: x, y: y).alpha > 0 {
            clippedBoundaryPixels += 1
        }
    }
    var retainedBoundaryPixels = 0
    for y in 60...68 {
        for x in 92...100 where surfacePixel(wireframePixels, x: x, y: y).alpha > 0 {
            retainedBoundaryPixels += 1
        }
    }
    #expect(clippedBoundaryPixels == 0)
    #expect(retainedBoundaryPixels > 0)
}

@Test(.timeLimit(.minutes(1)))
func viewportSurfaceGPURejectsUnboundedAttachments() throws {
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try ViewportSurfaceRenderer.attachmentByteCount(width: Int.max, height: 2)
    }
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try ViewportSurfaceRenderer.attachmentByteCount(width: 20_000, height: 20_000)
    }
}

@Test(.timeLimit(.minutes(1)))
func viewportSurfaceGPURejectsAnIncompleteRenderPassBeforeEncoding() throws {
    let (scene, _) = try presentationScene(
        references: [.authoredMesh(GeometrySourceID(rawValue: "mesh.presentation"))], transforms: [.identity]
    )
    let renderer = try ViewportSurfaceRenderer(plan: MeshSourcePresentationRenderPlan(scene: scene))
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try renderer.encode(
            into: renderer.makeCommandBuffer(), pass: MTLRenderPassDescriptor(), layout: surfaceTestLayout()
        )
    }
}

private func surfaceTestLayout(basis: ViewportProjectionBasis? = nil) -> ViewportLayout {
    ViewportLayout(
        modelBounds: CGRect(x: -1, y: -1, width: 2, height: 2),
        size: CGSize(width: 128, height: 128),
        basis: basis ?? ViewportProjectionBasis(
            mode: .orbit, xDirection: CGVector(dx: 1, dy: 0),
            yDirection: CGVector(dx: 0, dy: -1), zDirection: .zero
        ),
        verticalBounds: -1...1
    )
}

private func surfacePixels(
    _ renderer: ViewportSurfaceRenderer, layout: ViewportLayout,
    displayMode: ViewportDisplayMode = .solid,
    selected: SceneOccurrenceID? = nil, section: SectionAnalysisResult.Plane? = nil
) async throws -> [UInt8] {
    let colorDescriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .bgra8Unorm, width: 128, height: 128, mipmapped: false
    )
    colorDescriptor.usage = [.renderTarget]
    colorDescriptor.storageMode = .shared
    let color = try #require(renderer.device.makeTexture(descriptor: colorDescriptor))
    let depthDescriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .depth32Float, width: 128, height: 128, mipmapped: false
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
    try renderer.encode(
        into: command, pass: pass, layout: layout,
        displayMode: displayMode,
        state: { $0 == selected ? .selected : .normal }, sectionPlane: section
    )
    await withCheckedContinuation { continuation in
        command.addCompletedHandler { _ in continuation.resume() }
        command.commit()
    }
    #expect(command.status == .completed, "\(String(describing: command.error))")
    var pixels = [UInt8](repeating: 0, count: 128 * 128 * 4)
    pixels.withUnsafeMutableBytes { bytes in
        color.getBytes(bytes.baseAddress!, bytesPerRow: 128 * 4, from: MTLRegionMake2D(0, 0, 128, 128), mipmapLevel: 0)
    }
    return pixels
}

private func surfacePixel(_ pixels: [UInt8], x: Int, y: Int) -> (blue: UInt8, green: UInt8, red: UInt8, alpha: UInt8) {
    let offset = (y * 128 + x) * 4
    return (pixels[offset], pixels[offset + 1], pixels[offset + 2], pixels[offset + 3])
}

@Test(.timeLimit(.minutes(1)))
func meshSourcePresentationRendererConsumesCADOnlyThroughTheConcreteProtocolPath() throws {
    let cadReference = GeometrySourceReference.cad(
        sourceID: "cad.presentation",
        outputID: "cad.output"
    )
    let translation = try translationTransform(x: 10, y: 20, z: 30)
    let (scene, source) = try presentationScene(
        references: [cadReference],
        transforms: [translation]
    )
    let initialTelemetry = scene.copyTelemetry
    let sourceChunkIdentities = sourceChunkIdentitySummary(source)
    let renderer: any MeshSourcePresentationRendering = MeshSourcePresentationRenderer()
    let plan = try renderer.makePlan(for: scene)

    #expect(plan.itemCount == 1)
    #expect(plan.triangleCount == 2)
    var emittedCount = 0
    var cadCount = 0
    var sawTranslatedOrigin = false
    var sawTranslatedOppositeCorner = false
    try renderer.render(plan: plan) { triangle in
        emittedCount += 1
        if triangle.sourceReference == cadReference {
            cadCount += 1
        }
        if triangle.firstPosition == GeometryPoint3D(x: 10, y: 20, z: 30)
            || triangle.secondPosition == GeometryPoint3D(x: 10, y: 20, z: 30)
            || triangle.thirdPosition == GeometryPoint3D(x: 10, y: 20, z: 30) {
            sawTranslatedOrigin = true
        }
        if triangle.firstPosition == GeometryPoint3D(x: 11, y: 21, z: 30)
            || triangle.secondPosition == GeometryPoint3D(x: 11, y: 21, z: 30)
            || triangle.thirdPosition == GeometryPoint3D(x: 11, y: 21, z: 30) {
            sawTranslatedOppositeCorner = true
        }
    }

    #expect(emittedCount == 2)
    #expect(cadCount == 2)
    #expect(sawTranslatedOrigin)
    #expect(sawTranslatedOppositeCorner)
    #expect(scene.copyTelemetry == initialTelemetry)
    #expect(scene.items.allSatisfy { $0.copyTelemetry == GeometryCopyTelemetry() })
    #expect(sourceChunkIdentitySummary(source) == sourceChunkIdentities)
    #expect(sourceChunkIdentitySummary(scene.items[0].mesh) == sourceChunkIdentities)
}

@Test(.timeLimit(.minutes(1)))
func meshSourcePresentationRendererConsumesMeshOnlyThroughTheSameTraversal() throws {
    let sourceReference = GeometrySourceReference.authoredMesh(
        GeometrySourceID(rawValue: "mesh.presentation")
    )
    let (scene, _) = try presentationScene(
        references: [sourceReference],
        transforms: [.identity]
    )
    let renderer: any MeshSourcePresentationRendering = MeshSourcePresentationRenderer()
    let plan = try renderer.makePlan(for: scene)

    var emittedCount = 0
    var meshCount = 0
    var vertexIDSum: UInt64 = 0
    try renderer.render(plan: plan) { triangle in
        emittedCount += 1
        if triangle.sourceReference == sourceReference {
            meshCount += 1
        }
        vertexIDSum += triangle.firstVertexID.rawValue
            + triangle.secondVertexID.rawValue
            + triangle.thirdVertexID.rawValue
    }

    #expect(emittedCount == 2)
    #expect(meshCount == 2)
    #expect(vertexIDSum > 0)
}

@Test(.timeLimit(.minutes(1)))
func meshSourcePresentationRendererUsesGeometryEarClippingForConcaveFaces() throws {
    let source = try presentationConcaveSource()
    let sourceReference = GeometrySourceReference.authoredMesh(source.identity)
    let (scene, _) = try presentationScene(
        source: source,
        references: [sourceReference],
        transforms: [.identity]
    )
    let initialTelemetry = scene.copyTelemetry
    let initialChunkIdentities = sourceChunkIdentitySummary(source)
    let faceID = try #require(source.faceIDs.first)
    let expectedTriangles = try source.triangulate(faceID: faceID)
    let expectedKeys = Set(expectedTriangles.map(triangleKey))
    let renderer = MeshSourcePresentationRenderer()
    let plan = try renderer.makePlan(for: scene)

    var actualKeys: Set<String> = []
    var triangleArea = 0.0
    var emittedCount = 0
    try renderer.render(plan: plan) { triangle in
        emittedCount += 1
        actualKeys.insert(triangleKey(triangle))
        triangleArea += projectedTriangleArea(
            triangle.firstPosition,
            triangle.secondPosition,
            triangle.thirdPosition
        )
    }

    #expect(emittedCount == expectedTriangles.count)
    #expect(actualKeys == expectedKeys)
    #expect(actualKeys.contains(triangleKey(
        first: source.vertexIDs[0],
        second: source.vertexIDs[2],
        third: source.vertexIDs[3]
    )) == false)
    #expect(abs(triangleArea - projectedPolygonArea(source)) < 1e-9)
    #expect(plan.triangleCount == expectedTriangles.count)
    #expect(scene.copyTelemetry == initialTelemetry)
    #expect(sourceChunkIdentitySummary(source) == initialChunkIdentities)
    #expect(sourceChunkIdentitySummary(scene.items[0].mesh) == initialChunkIdentities)

    var secondPassCount = 0
    try renderer.render(plan: plan) { _ in
        secondPassCount += 1
    }
    #expect(secondPassCount == emittedCount)
}

@Test(.timeLimit(.minutes(1)))
func meshSourcePresentationRendererConsumesMixedSelectionsAndReusesSnapshotPlan() throws {
    let meshReference = GeometrySourceReference.authoredMesh(
        GeometrySourceID(rawValue: "mesh.presentation")
    )
    let cadReference = GeometrySourceReference.cad(
        sourceID: "cad.presentation",
        outputID: "cad.output"
    )
    let (scene, source) = try presentationScene(
        references: [cadReference, meshReference],
        transforms: [.identity, try translationTransform(x: -2, y: 0, z: 0)]
    )
    let renderer: any MeshSourcePresentationRendering = MeshSourcePresentationRenderer()
    let plan = try renderer.makePlan(for: scene)
    let initialSourceChunkIdentities = sourceChunkIdentitySummary(source)

    var firstPassCount = 0
    var firstPassCadCount = 0
    var firstPassMeshCount = 0
    var firstPassPositionSum = GeometryPoint3D(x: 0, y: 0, z: 0)
    try renderer.render(plan: plan) { triangle in
        firstPassCount += 1
        firstPassPositionSum.x += triangle.firstPosition.x
        firstPassPositionSum.y += triangle.firstPosition.y
        firstPassPositionSum.z += triangle.firstPosition.z
        if triangle.sourceReference == cadReference {
            firstPassCadCount += 1
        } else if triangle.sourceReference == meshReference {
            firstPassMeshCount += 1
        } else {
            Issue.record("The mixed presentation path emitted an unexpected source reference.")
        }
    }

    var secondPassCount = 0
    var secondPassPositionSum = GeometryPoint3D(x: 0, y: 0, z: 0)
    try renderer.render(plan: plan) { triangle in
        secondPassCount += 1
        secondPassPositionSum.x += triangle.firstPosition.x
        secondPassPositionSum.y += triangle.firstPosition.y
        secondPassPositionSum.z += triangle.firstPosition.z
    }

    #expect(plan.itemCount == 2)
    #expect(plan.triangleCount == 4)
    #expect(firstPassCount == 4)
    #expect(firstPassCadCount == 2)
    #expect(firstPassMeshCount == 2)
    #expect(secondPassCount == firstPassCount)
    #expect(secondPassPositionSum == firstPassPositionSum)
    #expect(sourceChunkIdentitySummary(source) == initialSourceChunkIdentities)
    #expect(scene.items.allSatisfy { $0.copyTelemetry == GeometryCopyTelemetry() })
}

@Test(.timeLimit(.minutes(1)))
func meshSourcePresentationRendererRejectsAuthorityAndBufferFailuresAsTypedErrors() throws {
    let sourceReference = GeometrySourceReference.authoredMesh(
        GeometrySourceID(rawValue: "mesh.presentation")
    )
    let (scene, source) = try presentationScene(
        references: [sourceReference],
        transforms: [.identity]
    )
    let item = scene.items[0]
    let mismatchedItem = UniversalViewportSceneItem(
        id: item.id,
        definitionID: item.definitionID,
        displayName: item.displayName,
        representationID: item.representationID,
        reference: .authoredMesh(GeometrySourceID(rawValue: "mesh.other")),
        mesh: source,
        copyTelemetry: item.copyTelemetry,
        worldTransform: item.worldTransform,
        worldBounds: item.worldBounds
    )
    let mismatchedScene = UniversalViewportScene(
        snapshotID: scene.snapshotID,
        projectID: scene.projectID,
        items: [mismatchedItem],
        copyTelemetry: scene.copyTelemetry
    )
    var authorityError: MeshSourcePresentationRenderError?
    do {
        _ = try MeshSourcePresentationRenderPlan(scene: mismatchedScene)
    } catch let error as MeshSourcePresentationRenderError {
        authorityError = error
    }
    #expect(authorityError?.code == .sourceAuthorityMismatch)

    let malformedSource = try sourceWithMissingCornerVertex(source: source)
    let malformedItem = UniversalViewportSceneItem(
        id: item.id,
        definitionID: item.definitionID,
        displayName: item.displayName,
        representationID: item.representationID,
        reference: sourceReference,
        mesh: malformedSource,
        worldTransform: item.worldTransform,
        worldBounds: item.worldBounds
    )
    let malformedScene = UniversalViewportScene(
        snapshotID: scene.snapshotID,
        projectID: scene.projectID,
        items: [malformedItem],
        copyTelemetry: scene.copyTelemetry
    )
    var vertexError: MeshSourcePresentationRenderError?
    do {
        _ = try MeshSourcePresentationRenderPlan(scene: malformedScene)
    } catch let error as MeshSourcePresentationRenderError {
        vertexError = error
    }
    #expect(vertexError?.code == .invalidVertexReference)
}

@Test(.timeLimit(.minutes(1)))
func meshSourcePresentationRendererMapsGeometryTriangulationFailures() throws {
    let nonPlanarSource = try presentationNonPlanarSource()
    let nonPlanarReference = GeometrySourceReference.authoredMesh(nonPlanarSource.identity)
    let nonPlanarScene = try presentationScene(
        source: nonPlanarSource,
        references: [nonPlanarReference],
        transforms: [.identity]
    ).scene
    var nonPlanarError: MeshSourcePresentationRenderError?
    do {
        _ = try MeshSourcePresentationRenderPlan(scene: nonPlanarScene)
    } catch let error as MeshSourcePresentationRenderError {
        nonPlanarError = error
    }
    #expect(nonPlanarError?.code == .nonPlanar)

    let degenerateSource = try presentationDegenerateSource()
    let degenerateReference = GeometrySourceReference.authoredMesh(degenerateSource.identity)
    let degenerateScene = try presentationScene(
        source: degenerateSource,
        references: [degenerateReference],
        transforms: [.identity]
    ).scene
    var degenerateError: MeshSourcePresentationRenderError?
    do {
        _ = try MeshSourcePresentationRenderPlan(scene: degenerateScene)
    } catch let error as MeshSourcePresentationRenderError {
        degenerateError = error
    }
    #expect(degenerateError?.code == .degenerate)
}

@Test(.timeLimit(.minutes(1)))
func meshSourcePresentationRendererMapsFaceRangeArithmeticOverflow() throws {
    let (scene, source) = try presentationScene(
        references: [.authoredMesh(GeometrySourceID(rawValue: "mesh.presentation"))],
        transforms: [.identity]
    )
    let malformedSource = try sourceWithFaceCornerRange(
        source: source,
        range: MeshIndexRange(start: Int.max, count: 3)
    )
    let item = scene.items[0]
    let malformedItem = UniversalViewportSceneItem(
        id: item.id,
        definitionID: item.definitionID,
        displayName: item.displayName,
        representationID: item.representationID,
        reference: item.sourceReference,
        mesh: malformedSource,
        worldTransform: item.worldTransform,
        worldBounds: item.worldBounds
    )
    let malformedScene = UniversalViewportScene(
        snapshotID: scene.snapshotID,
        projectID: scene.projectID,
        items: [malformedItem],
        copyTelemetry: scene.copyTelemetry
    )
    var error: MeshSourcePresentationRenderError?

    do {
        _ = try MeshSourcePresentationRenderPlan(scene: malformedScene)
    } catch let caught as MeshSourcePresentationRenderError {
        error = caught
    }

    #expect(error?.code == .sizeOverflow)
}

@Test(.timeLimit(.minutes(1)))
func meshSourcePresentationRendererReportsTransformFailureDuringConstruction() throws {
    let sourceReference = GeometrySourceReference.authoredMesh(
        GeometrySourceID(rawValue: "mesh.presentation")
    )
    let (scene, source) = try presentationScene(
        references: [sourceReference],
        transforms: [.identity]
    )
    let item = scene.items[0]
    let pointAtInfinityTransform = try GeometryTransform3D(values: [
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 0,
    ])
    let invalidTransformItem = UniversalViewportSceneItem(
        id: item.id,
        definitionID: item.definitionID,
        displayName: item.displayName,
        representationID: item.representationID,
        reference: sourceReference,
        mesh: source,
        worldTransform: pointAtInfinityTransform,
        worldBounds: item.worldBounds
    )
    let invalidTransformScene = UniversalViewportScene(
        snapshotID: scene.snapshotID,
        projectID: scene.projectID,
        items: [invalidTransformItem],
        copyTelemetry: scene.copyTelemetry
    )
    // The plan transforms every vertex exactly once while it is built, so a
    // transform that cannot produce a finite point is refused at construction
    // and no partially transformed plan is ever published.
    var error: MeshSourcePresentationRenderError?
    do {
        _ = try MeshSourcePresentationRenderer().makePlan(for: invalidTransformScene)
    } catch let caught as MeshSourcePresentationRenderError {
        error = caught
    }
    #expect(error?.code == .transformFailure)

    // Admission must happen before the first transformed-position allocation.
    // The deliberately unprojectable transform detects a late limit check.
    for (limits, expectedCode) in [
        (MeshTriangulationLimits(maxFaceCornerCount: 3, maxNonConvexWorkUnits: 0), MeshSourcePresentationRenderError.Code.budgetExceeded),
        (MeshTriangulationLimits(maxFaceCornerCount: 2, maxNonConvexWorkUnits: 0), .failed),
    ] {
        var admissionError: MeshSourcePresentationRenderError?
        do {
            _ = try MeshSourcePresentationRenderPlan(scene: invalidTransformScene, limits: limits)
        } catch let caught as MeshSourcePresentationRenderError {
            admissionError = caught
        }
        #expect(admissionError?.code == expectedCode)
    }
}

@Test(.timeLimit(.minutes(1)))
func meshSourcePresentationRenderPlanUsesBoundedSourceOrderForHighSegmentCylinder() throws {
    let segmentCount = 6_284
    let source = try presentationHighSegmentCylinderSource(segmentCount: segmentCount)
    let sourceReference = GeometrySourceReference.authoredMesh(source.identity)
    let scene = try presentationScene(
        source: source,
        references: [sourceReference],
        transforms: [.identity]
    ).scene
    let initialChunkIdentities = sourceChunkIdentitySummary(source)
    let start = Date()
    let renderer = MeshSourcePresentationRenderer()
    let plan = try renderer.makePlan(for: scene)
    let elapsed = Date().timeIntervalSince(start)

    #expect(elapsed < 2.0)
    #expect(plan.itemCount == 1)
    #expect(plan.triangleCount == 4 * segmentCount - 4)
    #expect(plan.telemetry.faceVisits == segmentCount + 2)
    #expect(plan.telemetry.cornerVisits == 6 * segmentCount)
    #expect(plan.telemetry.indexedVertexLookups == 6 * segmentCount)
    #expect(plan.telemetry.positionReads == 6 * segmentCount)
    #expect(plan.telemetry.scratchPositionValues == 6 * segmentCount)
    #expect(plan.telemetry.nonConvexWorkUnits == 0)
    #expect(plan.telemetry.globalIdentifierScans == 0)
    #expect(plan.telemetry.sourcePositionMaterializations == 0)
    #expect(sourceChunkIdentitySummary(scene.items[0].mesh) == initialChunkIdentities)
    #expect(scene.items[0].copyTelemetry == GeometryCopyTelemetry())

    var emittedCount = 0
    try renderer.render(plan: plan) { triangle in
        emittedCount += 1
        #expect(triangle.sourceReference == sourceReference)
    }
    #expect(emittedCount == 4 * segmentCount - 4)
}

@Test(.timeLimit(.minutes(1)))
func meshSourcePresentationRenderPlanReportsConcaveBudgetFailureWithoutPartialPlan() throws {
    let source = try presentationConcaveSource()
    let sourceReference = GeometrySourceReference.authoredMesh(source.identity)
    let scene = try presentationScene(
        source: source,
        references: [sourceReference],
        transforms: [.identity]
    ).scene

    var error: MeshSourcePresentationRenderError?
    do {
        _ = try MeshSourcePresentationRenderPlan(
            scene: scene,
            limits: MeshTriangulationLimits(
                maxFaceCornerCount: 16_384,
                maxNonConvexWorkUnits: 0
            )
        )
    } catch let caught as MeshSourcePresentationRenderError {
        error = caught
    }

    #expect(error?.code == .budgetExceeded)
}

@Test(.timeLimit(.minutes(1)))
func meshSourcePresentationRenderPlanTransformsEachSourceVertexExactlyOnce() throws {
    let firstReference = GeometrySourceReference.cad(
        sourceID: "cad.presentation.first",
        outputID: "cad.output"
    )
    let secondReference = GeometrySourceReference.cad(
        sourceID: "cad.presentation.second",
        outputID: "cad.output"
    )
    let translation = try translationTransform(x: 10, y: 20, z: 30)
    let (scene, source) = try presentationScene(
        references: [firstReference, secondReference],
        transforms: [.identity, translation]
    )
    let plan = try MeshSourcePresentationRenderer().makePlan(for: scene)

    // One transformed position per source vertex per occurrence, not one per
    // triangle corner: a shared corner is transformed once and then indexed.
    #expect(plan.itemCount == 2)
    #expect(plan.triangleCount == 4)
    #expect(plan.positionCount == 2 * source.vertexIDs.count)
    #expect(plan.positionCount < 3 * plan.triangleCount)
    #expect(plan.retainedByteCount > 0)
    #expect(plan.retainedByteCount <= MeshSourcePresentationPlanLimits.standard.maxRetainedByteCount)

    // The indexed positions still carry the same world geometry the previous
    // per-corner traversal produced.
    var expectedPositions: Set<String> = []
    for index in source.vertexPositions.indices {
        let point = source.vertexPositions[index]
        expectedPositions.insert("\(point.x),\(point.y),\(point.z)")
        let translated = try translation.applying(to: point)
        expectedPositions.insert("\(translated.x),\(translated.y),\(translated.z)")
    }
    var emittedCount = 0
    plan.forEachTriangle { triangle in
        emittedCount += 1
        for point in [triangle.firstPosition, triangle.secondPosition, triangle.thirdPosition] {
            #expect(expectedPositions.contains("\(point.x),\(point.y),\(point.z)"))
        }
    }
    #expect(emittedCount == 4)
}

@Test(.timeLimit(.minutes(1)))
func meshSourcePresentationRenderPlanRefusesEachDerivedResourceAboveItsLimit() throws {
    let firstReference = GeometrySourceReference.cad(
        sourceID: "cad.presentation.first",
        outputID: "cad.output"
    )
    let secondReference = GeometrySourceReference.cad(
        sourceID: "cad.presentation.second",
        outputID: "cad.output"
    )
    let (scene, _) = try presentationScene(
        references: [firstReference, secondReference],
        transforms: [.identity, .identity]
    )
    let hardMaximum = MeshSourcePresentationPlanLimits.hardMaximum
    let lowered: [(String, MeshSourcePresentationPlanLimits)] = [
        ("item", MeshSourcePresentationPlanLimits(
            maxItemCount: 1,
            maxPositionCount: hardMaximum.maxPositionCount,
            maxTriangleCount: hardMaximum.maxTriangleCount,
            maxRetainedByteCount: hardMaximum.maxRetainedByteCount
        )),
        ("position", MeshSourcePresentationPlanLimits(
            maxItemCount: hardMaximum.maxItemCount,
            maxPositionCount: 3,
            maxTriangleCount: hardMaximum.maxTriangleCount,
            maxRetainedByteCount: hardMaximum.maxRetainedByteCount
        )),
        ("triangle", MeshSourcePresentationPlanLimits(
            maxItemCount: hardMaximum.maxItemCount,
            maxPositionCount: hardMaximum.maxPositionCount,
            maxTriangleCount: 1,
            maxRetainedByteCount: hardMaximum.maxRetainedByteCount
        )),
        ("retained byte", MeshSourcePresentationPlanLimits(
            maxItemCount: hardMaximum.maxItemCount,
            maxPositionCount: hardMaximum.maxPositionCount,
            maxTriangleCount: hardMaximum.maxTriangleCount,
            maxRetainedByteCount: 1
        )),
    ]

    for (dimension, planLimits) in lowered {
        var error: MeshSourcePresentationRenderError?
        do {
            _ = try MeshSourcePresentationRenderPlan(scene: scene, planLimits: planLimits)
        } catch let caught as MeshSourcePresentationRenderError {
            error = caught
        }
        #expect(error?.code == .resourceExhausted, "\(dimension) limit was not enforced")
    }
}

@Test(.timeLimit(.minutes(1)))
func meshSourcePresentationRenderPlanRefusesACallerThatWidensTheModuleCeiling() throws {
    let reference = GeometrySourceReference.cad(
        sourceID: "cad.presentation",
        outputID: "cad.output"
    )
    let (scene, _) = try presentationScene(
        references: [reference],
        transforms: [.identity]
    )
    let hardMaximum = MeshSourcePresentationPlanLimits.hardMaximum
    let widened = MeshSourcePresentationPlanLimits(
        maxItemCount: hardMaximum.maxItemCount,
        maxPositionCount: hardMaximum.maxPositionCount,
        maxTriangleCount: hardMaximum.maxTriangleCount + 1,
        maxRetainedByteCount: hardMaximum.maxRetainedByteCount
    )

    var error: MeshSourcePresentationRenderError?
    do {
        _ = try MeshSourcePresentationRenderPlan(scene: scene, planLimits: widened)
    } catch let caught as MeshSourcePresentationRenderError {
        error = caught
    }
    #expect(error?.code == .invalidLimit)
}

@Test(.timeLimit(.minutes(1)))
func meshSourcePresentationRenderPlanStopsWhenItsTaskIsCancelled() async throws {
    let reference = GeometrySourceReference.cad(
        sourceID: "cad.presentation",
        outputID: "cad.output"
    )
    let (scene, _) = try presentationScene(
        references: [reference],
        transforms: [.identity]
    )
    // The gate keeps the build from starting until cancellation has been
    // requested, so the test observes cooperative cancellation rather than a
    // race between cancel and completion.
    let gate = AsyncStream<Void>.makeStream()
    let task = Task { () throws -> MeshSourcePresentationRenderPlan in
        var iterator = gate.stream.makeAsyncIterator()
        _ = await iterator.next()
        return try MeshSourcePresentationRenderPlan(scene: scene)
    }
    task.cancel()
    gate.continuation.finish()

    await #expect(throws: CancellationError.self) {
        _ = try await task.value
    }
}

@Test(.timeLimit(.minutes(1)))
func presentationPlanCancellationStopsAnInFlightLargeBuild() async throws {
    let source = try presentationHighSegmentCylinderSource(segmentCount: 6_284)
    let scene = try presentationScene(
        source: source,
        references: Array(repeating: .authoredMesh(source.identity), count: 12),
        transforms: Array(repeating: .identity, count: 12)
    ).scene
    let started = Mutex(false)
    let finished = Mutex(false)
    let task = Task.detached {
        started.withLock { $0 = true }
        defer { finished.withLock { $0 = true } }
        return try MeshSourcePresentationRenderPlan(scene: scene)
    }
    while !started.withLock({ $0 }) { await Task.yield() }
    try await Task.sleep(for: .milliseconds(3))
    #expect(!finished.withLock { $0 }, "The fixture must still be building when cancellation is requested.")
    let clock = ContinuousClock()
    let cancelledAt = clock.now
    task.cancel()
    await #expect(throws: CancellationError.self) { _ = try await task.value }
    let latency = cancelledAt.duration(to: clock.now)
    #expect(finished.withLock { $0 })
    #expect(latency < .milliseconds(100), "Actual worker exit must meet the cancellation budget: \(latency).")
}

private func presentationHighSegmentCylinderSource(segmentCount: Int) throws -> MeshSource {
    let radius = 0.035
    let length = 0.45
    let centerX = 10.0
    let centerY = -7.0
    var builder = MeshSourceBuilder(identity: "mesh.presentation-high-segment-cylinder")
    try builder.reserveCapacity(
        vertexCount: 2 * segmentCount,
        faceCount: segmentCount + 2,
        cornerCount: 6 * segmentCount
    )
    var bottomVertices: [MeshVertexID] = []
    bottomVertices.reserveCapacity(segmentCount)
    var topVertices: [MeshVertexID] = []
    topVertices.reserveCapacity(segmentCount)
    for index in 0..<segmentCount {
        let angle = 2.0 * Double.pi * Double(index) / Double(segmentCount)
        let x = centerX + radius * cos(angle)
        let y = centerY + radius * sin(angle)
        bottomVertices.append(
            try builder.addVertex(
                GeometryPoint3D(
                    x: x,
                    y: y,
                    z: 0
                )
            )
        )
        topVertices.append(
            try builder.addVertex(
                GeometryPoint3D(
                    x: x,
                    y: y,
                    z: length
                )
            )
        )
    }
    _ = try builder.addFace(vertexIDs: bottomVertices.reversed())
    _ = try builder.addFace(vertexIDs: topVertices)
    for index in 0..<segmentCount {
        let nextIndex = (index + 1) % segmentCount
        _ = try builder.addFace(vertexIDs: [
            bottomVertices[index],
            bottomVertices[nextIndex],
            topVertices[nextIndex],
            topVertices[index],
        ])
    }
    return try builder.build()
}

private func presentationScene(
    source providedSource: MeshSource? = nil,
    references: [GeometrySourceReference],
    transforms: [GeometryTransform3D]
) throws -> (scene: UniversalViewportScene, source: MeshSource) {
    guard references.count == transforms.count, references.isEmpty == false else {
        throw MeshSourcePresentationRenderError(
            code: .invalidSceneItem,
            message: "Presentation test scenes require one transform per source reference."
        )
    }
    let source: MeshSource
    if let providedSource {
        source = providedSource
    } else {
        source = try presentationQuadSource()
    }
    let projectID = ProjectID(rawValue: "project.presentation-render")
    var objectDefinitions: [ObjectDefinitionID: ObjectDefinition] = [:]
    var occurrences: [SceneOccurrenceID: SceneOccurrence] = [:]
    var evaluatedOccurrences: [SceneOccurrenceID: EvaluatedOccurrenceSnapshot] = [:]
    var authoredMeshAssets: [GeometrySourceID: AuthoredMeshAsset] = [:]
    var rootOccurrenceIDs: [SceneOccurrenceID] = []

    for index in references.indices {
        let definitionID = ObjectDefinitionID(rawValue: "object.presentation-render.\(index)")
        let representationID = GeometryRepresentationID(rawValue: "representation.presentation-render.\(index)")
        let occurrenceID = SceneOccurrenceID(rawValue: "occurrence.presentation-render.\(index)")
        let reference = references[index]
        objectDefinitions[definitionID] = ObjectDefinition(
            id: definitionID,
            name: "Presentation \(index)",
            representations: presentationRepresentations(
                id: representationID,
                reference: reference
            )
        )
        occurrences[occurrenceID] = SceneOccurrence(
            id: occurrenceID,
            definitionID: definitionID
        )
        let transform = transforms[index]
        evaluatedOccurrences[occurrenceID] = EvaluatedOccurrenceSnapshot(
            occurrenceID: occurrenceID,
            definitionID: definitionID,
            representationID: representationID,
            reference: reference,
            mesh: source,
            worldTransform: transform,
            worldBounds: try source.bounds().transformed(by: transform)
        )
        rootOccurrenceIDs.append(occurrenceID)
        if case .authoredMesh(let sourceID) = reference {
            authoredMeshAssets[sourceID] = try AuthoredMeshAsset(
                source: source,
                provenance: .created
            )
        }
    }

    let project = try ProjectSourceModel(
        id: projectID,
        name: "Presentation rendering",
        authoredMeshAssets: authoredMeshAssets,
        objectDefinitions: objectDefinitions,
        occurrences: occurrences,
        rootOccurrenceIDs: rootOccurrenceIDs
    )
    let snapshot = EvaluatedProjectSnapshot(
        id: EvaluationSnapshotID(
            projectID: projectID,
            purpose: .presentation,
            sourceRevision: DocumentTransactionRevision()
        ),
        projectID: projectID,
        occurrences: evaluatedOccurrences,
        copyTelemetry: GeometryCopyTelemetry()
    )
    return (
        try UniversalViewportSceneBuilder().build(from: snapshot, project: project),
        source
    )
}

private func presentationQuadSource(reversed: Bool = false) throws -> MeshSource {
    var builder = MeshSourceBuilder(identity: GeometrySourceID(rawValue: "mesh.presentation"))
    try builder.reserveCapacity(vertexCount: 4, faceCount: 1, cornerCount: 4)
    let first = try builder.addVertex(GeometryPoint3D(x: 0, y: 0, z: 0))
    let second = try builder.addVertex(GeometryPoint3D(x: 1, y: 0, z: 0))
    let third = try builder.addVertex(GeometryPoint3D(x: 1, y: 1, z: 0))
    let fourth = try builder.addVertex(GeometryPoint3D(x: 0, y: 1, z: 0))
    _ = try builder.addFace(
        vertexIDs: reversed ? [first, fourth, third, second] : [first, second, third, fourth]
    )
    return try builder.build()
}

private func presentationTriangleSource() throws -> MeshSource {
    var builder = MeshSourceBuilder(identity: GeometrySourceID(rawValue: "mesh.presentation-triangle"))
    try builder.reserveCapacity(vertexCount: 3, faceCount: 1, cornerCount: 3)
    let first = try builder.addVertex(GeometryPoint3D(x: 0, y: 0, z: 0))
    let second = try builder.addVertex(GeometryPoint3D(x: 1, y: 0, z: 0))
    let third = try builder.addVertex(GeometryPoint3D(x: 0, y: 1, z: 0))
    _ = try builder.addFace(vertexIDs: [first, second, third])
    return try builder.build()
}

private func presentationPointCloudSource() throws -> MeshSource {
    var builder = MeshSourceBuilder(identity: GeometrySourceID(rawValue: "mesh.presentation-points"))
    try builder.reserveCapacity(vertexCount: 3, faceCount: 0, cornerCount: 0)
    _ = try builder.addVertex(GeometryPoint3D(x: 0, y: 0, z: 0))
    _ = try builder.addVertex(GeometryPoint3D(x: 1, y: 0, z: 0))
    _ = try builder.addVertex(GeometryPoint3D(x: 0, y: 1, z: 0))
    return try builder.build()
}

private func presentationConcaveSource() throws -> MeshSource {
    var builder = MeshSourceBuilder(identity: GeometrySourceID(rawValue: "mesh.concave"))
    let points = [
        GeometryPoint3D(x: 0, y: 0, z: 0),
        GeometryPoint3D(x: 3, y: 0, z: 0),
        GeometryPoint3D(x: 3, y: 3, z: 0),
        GeometryPoint3D(x: 1, y: 1, z: 0),
        GeometryPoint3D(x: 0, y: 3, z: 0),
    ]
    try builder.reserveCapacity(vertexCount: points.count, faceCount: 1, cornerCount: points.count)
    let vertices = try points.map { try builder.addVertex($0) }
    _ = try builder.addFace(vertexIDs: vertices)
    return try builder.build()
}

private func presentationNonPlanarSource() throws -> MeshSource {
    var builder = MeshSourceBuilder(identity: GeometrySourceID(rawValue: "mesh.nonplanar"))
    let points = [
        GeometryPoint3D(x: 0, y: 0, z: 0),
        GeometryPoint3D(x: 1, y: 0, z: 0),
        GeometryPoint3D(x: 2, y: 1, z: 0.25),
        GeometryPoint3D(x: 0, y: 1, z: 0),
    ]
    try builder.reserveCapacity(vertexCount: points.count, faceCount: 1, cornerCount: points.count)
    let vertices = try points.map { try builder.addVertex($0) }
    _ = try builder.addFace(vertexIDs: vertices)
    return try builder.build()
}

private func presentationDegenerateSource() throws -> MeshSource {
    var builder = MeshSourceBuilder(identity: GeometrySourceID(rawValue: "mesh.degenerate"))
    let points = [
        GeometryPoint3D(x: 0, y: 0, z: 0),
        GeometryPoint3D(x: 1, y: 0, z: 0),
        GeometryPoint3D(x: 2, y: 0, z: 0),
        GeometryPoint3D(x: 3, y: 0, z: 0),
    ]
    try builder.reserveCapacity(vertexCount: points.count, faceCount: 1, cornerCount: points.count)
    let vertices = try points.map { try builder.addVertex($0) }
    _ = try builder.addFace(vertexIDs: vertices)
    return try builder.build()
}

private func presentationRepresentations(
    id: GeometryRepresentationID,
    reference: GeometrySourceReference
) -> GeometryRepresentationSet {
    GeometryRepresentationSet(
        representations: [id: GeometryRepresentation(id: id, source: reference)],
        selection: GeometryRepresentationSelection(modeling: id, presentation: id)
    )
}

private func translationTransform(x: Double, y: Double, z: Double) throws -> GeometryTransform3D {
    try GeometryTransform3D(values: [
        1, 0, 0, x,
        0, 1, 0, y,
        0, 0, 1, z,
        0, 0, 0, 1,
    ])
}

private func sourceWithMissingCornerVertex(source: MeshSource) throws -> MeshSource {
    let encoded = try JSONEncoder().encode(source)
    guard var object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else {
        throw MeshSourcePresentationRenderError(
            code: .invalidVertexReference,
            message: "Presentation test source did not encode as an object."
        )
    }
    object["cornerVertexIDs"] = [
        ["rawValue": 0],
        ["rawValue": 1],
        ["rawValue": 2],
        ["rawValue": 99],
    ]
    let malformedData = try JSONSerialization.data(withJSONObject: object)
    return try JSONDecoder().decode(MeshSource.self, from: malformedData)
}

private func sourceWithFaceCornerRange(
    source: MeshSource,
    range: MeshIndexRange
) throws -> MeshSource {
    let encoded = try JSONEncoder().encode(source)
    guard var object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any],
          var ranges = object["faceCornerRanges"] as? [[String: Any]],
          !ranges.isEmpty else {
        throw MeshSourcePresentationRenderError(
            code: .invalidFaceRange,
            message: "Presentation test source did not encode a face range."
        )
    }
    ranges[0] = ["start": range.start, "count": range.count]
    object["faceCornerRanges"] = ranges
    let malformedData = try JSONSerialization.data(withJSONObject: object)
    return try JSONDecoder().decode(MeshSource.self, from: malformedData)
}

private func triangleKey(_ triangle: MeshSourcePresentationTriangle) -> String {
    triangleKey(
        first: triangle.firstVertexID,
        second: triangle.secondVertexID,
        third: triangle.thirdVertexID
    )
}

private func triangleKey(_ triangle: MeshTriangle) -> String {
    triangleKey(
        first: triangle.vertexIDs.0,
        second: triangle.vertexIDs.1,
        third: triangle.vertexIDs.2
    )
}

private func triangleKey(
    first: MeshVertexID,
    second: MeshVertexID,
    third: MeshVertexID
) -> String {
    "\(first.rawValue),\(second.rawValue),\(third.rawValue)"
}

private func projectedTriangleArea(
    _ first: GeometryPoint3D,
    _ second: GeometryPoint3D,
    _ third: GeometryPoint3D
) -> Double {
    abs(
        (second.x - first.x) * (third.y - first.y)
            - (second.y - first.y) * (third.x - first.x)
    ) / 2
}

private func projectedPolygonArea(_ source: MeshSource) -> Double {
    var area = 0.0
    for index in source.vertexPositions.indices {
        let current = source.vertexPositions[index]
        let next = source.vertexPositions[(index + 1) % source.vertexPositions.count]
        area += current.x * next.y - next.x * current.y
    }
    return abs(area) / 2
}

private func sourceChunkIdentitySummary(_ source: MeshSource) -> [[ObjectIdentifier]] {
    [
        source.vertexIDs.storage.chunkIdentities,
        source.vertexPositions.storage.chunkIdentities,
        source.edgeIDs.storage.chunkIdentities,
        source.edgeEndpoints.storage.chunkIdentities,
        source.faceIDs.storage.chunkIdentities,
        source.faceCornerRanges.storage.chunkIdentities,
        source.cornerIDs.storage.chunkIdentities,
        source.cornerVertexIDs.storage.chunkIdentities,
        source.cornerEdgeIDs.storage.chunkIdentities,
    ]
}

// MARK: - Per-occurrence consumption

@Test
func presentationOccurrenceViewExposesFewerPositionsThanTriangleCorners() throws {
    let fixture = try presentationScene(
        references: [.authoredMesh(GeometrySourceID(rawValue: "mesh.presentation"))],
        transforms: [try translationTransform(x: 0, y: 0, z: 0)]
    )
    let plan = try MeshSourcePresentationRenderPlan(scene: fixture.scene)

    var visitedOccurrences = 0
    plan.forEachOccurrence { occurrence in
        visitedOccurrences += 1
        // The quad triangulates into two triangles that share two vertices, so
        // projecting the retained positions costs fewer projections than
        // projecting every triangle corner.
        #expect(occurrence.positions.count < 3 * occurrence.triangleCount)
        #expect(occurrence.triangleCount == plan.triangleCount)
    }
    #expect(visitedOccurrences == plan.itemCount)
}

@Test
func presentationOccurrenceIndicesSelectTheSamePositionsAsTriangleTraversal() throws {
    let fixture = try presentationScene(
        references: [
            .authoredMesh(GeometrySourceID(rawValue: "mesh.presentation")),
            .authoredMesh(GeometrySourceID(rawValue: "mesh.presentation")),
        ],
        transforms: [
            try translationTransform(x: 0, y: 0, z: 0),
            try translationTransform(x: 4, y: 0, z: 0),
        ]
    )
    let plan = try MeshSourcePresentationRenderPlan(scene: fixture.scene)

    var traversed: [GeometryPoint3D] = []
    plan.forEachTriangle { triangle in
        traversed.append(triangle.firstPosition)
        traversed.append(triangle.secondPosition)
        traversed.append(triangle.thirdPosition)
    }

    var indexed: [GeometryPoint3D] = []
    plan.forEachOccurrence { occurrence in
        for index in 0..<occurrence.triangleCount {
            let indices = occurrence.positionIndices(at: index)
            indexed.append(occurrence.positions[indices.first])
            indexed.append(occurrence.positions[indices.second])
            indexed.append(occurrence.positions[indices.third])
        }
    }

    #expect(indexed == traversed)
    #expect(indexed.count == 3 * plan.triangleCount)
}
