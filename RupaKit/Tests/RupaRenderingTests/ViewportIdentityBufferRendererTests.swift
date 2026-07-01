import CoreGraphics
import RupaCore
import SwiftCAD
import Testing
@testable import RupaRendering

@Test func viewportIdentityBufferRendererSamplesGeneratedTopologyHits() throws {
    let scene = identityBufferGeneratedTopologyScene()
    let viewportSize = CGSize(width: 240.0, height: 180.0)
    let layout = try #require(ViewportLayout(scene: scene, size: viewportSize))
    let plan = ViewportIdentityPickRenderPlanBuilder().build(scene: scene, layout: layout)
    let renderer = try ViewportIdentityBufferRenderer()
    let faceComponentID = SelectionComponentID.generatedTopology(
        "feature:body:subshape:identity:face:front"
    )
    let vertexComponentID = SelectionComponentID.generatedTopology(
        "feature:body:subshape:identity:vertex:frontBottomLeft"
    )

    let buffer = try renderer.render(plan: plan, viewportSize: viewportSize)
    let faceSample = try buffer.sample(
        at: layout.project(Point3D(x: 0.0, y: 0.0, z: 0.0))
    )
    let vertexSample = try buffer.sample(
        at: layout.project(Point3D(x: -0.020, y: 0.0, z: -0.020))
    )
    let backgroundSample = try buffer.sample(at: CGPoint(x: 4.0, y: 4.0))

    #expect(faceSample.rawValue != ViewportPickIdentity.backgroundRawValue)
    #expect(faceSample.hit?.pickingBackend == .identityBuffer)
    #expect(faceSample.hit?.selectionComponent == .face(faceComponentID))
    #expect(vertexSample.hit?.selectionComponent == .vertex(vertexComponentID))
    #expect(backgroundSample.rawValue == ViewportPickIdentity.backgroundRawValue)
    #expect(backgroundSample.identity == nil)
    #expect(backgroundSample.hit == nil)
}

@Test func viewportIdentityBufferRendererFiltersGeneratedTopologyBySelectionPolicy() throws {
    let scene = identityBufferGeneratedTopologyScene()
    let viewportSize = CGSize(width: 240.0, height: 180.0)
    let layout = try #require(ViewportLayout(scene: scene, size: viewportSize))
    let renderer = try ViewportIdentityBufferRenderer()
    let samplePoint = layout.project(Point3D(x: -0.018, y: 0.0, z: -0.018))
    let faceComponentID = SelectionComponentID.generatedTopology(
        "feature:body:subshape:identity:face:front"
    )
    let vertexComponentID = SelectionComponentID.generatedTopology(
        "feature:body:subshape:identity:vertex:frontBottomLeft"
    )

    let facePlan = ViewportIdentityPickRenderPlanBuilder().build(
        scene: scene,
        layout: layout,
        selectionHitPolicy: .face
    )
    let vertexPlan = ViewportIdentityPickRenderPlanBuilder().build(
        scene: scene,
        layout: layout,
        selectionHitPolicy: .vertex
    )
    let allPlan = ViewportIdentityPickRenderPlanBuilder().build(scene: scene, layout: layout)

    let faceSample = try renderer.render(plan: facePlan, viewportSize: viewportSize)
        .sample(at: samplePoint)
    let vertexSample = try renderer.render(plan: vertexPlan, viewportSize: viewportSize)
        .sample(at: samplePoint)
    let allSample = try renderer.render(plan: allPlan, viewportSize: viewportSize)
        .sample(at: samplePoint)

    #expect(facePlan.index.count == 1)
    #expect(vertexPlan.index.count == 1)
    #expect(faceSample.hit?.selectionComponent == .face(faceComponentID))
    #expect(vertexSample.hit?.selectionComponent == .vertex(vertexComponentID))
    #expect(allSample.hit?.selectionComponent == .vertex(vertexComponentID))
}

@Test func viewportIdentityBufferRendererReportsRenderReadbackMetrics() throws {
    let scene = identityBufferGeneratedTopologyScene()
    let viewportSize = CGSize(width: 240.0, height: 180.0)
    let layout = try #require(ViewportLayout(scene: scene, size: viewportSize))
    let plan = ViewportIdentityPickRenderPlanBuilder().build(scene: scene, layout: layout)
    let renderer = try ViewportIdentityBufferRenderer()

    let buffer = try renderer.render(plan: plan, viewportSize: viewportSize)
    let metrics = try #require(buffer.renderMetrics)

    #expect(metrics.viewportWidth == 240)
    #expect(metrics.viewportHeight == 180)
    #expect(metrics.encodedCommandCount == plan.drawItems.count)
    #expect(metrics.encodedPointCount > 0)
    #expect(metrics.encodedMeshPrimitiveCacheHitCount == 0)
    #expect(metrics.encodedMeshPrimitiveCacheMissCount == 0)
    #expect(metrics.pixelCount == buffer.rawValues.count)
    #expect(metrics.encodeDurationSeconds >= 0.0)
    #expect(metrics.gpuDurationSeconds >= 0.0)
    #expect(metrics.readbackDurationSeconds >= 0.0)
    #expect(metrics.totalDurationSeconds >= metrics.readbackDurationSeconds)
}

@Test func viewportIdentityPickRenderPlanUsesViewportLocalCoordinatesForKilometerOrigin() throws {
    let origin = Point3D(x: 1_000_000.0, y: 2_000.0, z: -1_000_000.0)
    let scene = identityBufferGeneratedTopologyScene(origin: origin)
    let viewportSize = CGSize(width: 240.0, height: 180.0)
    let layout = try #require(ViewportLayout(scene: scene, size: viewportSize))
    let plan = ViewportIdentityPickRenderPlanBuilder().build(scene: scene, layout: layout)
    let renderer = try ViewportIdentityBufferRenderer()
    let faceComponentID = SelectionComponentID.generatedTopology(
        "feature:body:subshape:identity:face:front"
    )

    let encodedPoints = identityPlanPoints(plan)
    let buffer = try renderer.render(plan: plan, viewportSize: viewportSize)
    let sample = try buffer.sample(at: layout.project(origin))
    let finitePointCount = encodedPoints.filter { point in
        point.x.isFinite && point.y.isFinite
    }.count
    let localPointCount = encodedPoints.filter { point in
        abs(point.x) < 10_000.0 && abs(point.y) < 10_000.0
    }.count
    let localDepthCount = plan.drawItems.filter { item in
        guard let depth = item.depth else {
            return true
        }
        return depth.isFinite && abs(depth) < 1.0
    }.count

    #expect(layout.renderOrigin.x == origin.x)
    #expect(abs(layout.renderOrigin.y - (origin.y + 0.010)) < 1.0e-12)
    #expect(layout.renderOrigin.z == origin.z)
    #expect(encodedPoints.isEmpty == false)
    #expect(finitePointCount == encodedPoints.count)
    #expect(localPointCount == encodedPoints.count)
    #expect(localDepthCount == plan.drawItems.count)
    #expect(sample.hit?.pickingBackend == .identityBuffer)
    #expect(sample.hit?.selectionComponent == .face(faceComponentID))
}

@Test func viewportIdentityBufferRendererCachesStableMeshPrimitiveEncoding() throws {
    let scene = identityBufferMeshFallbackScene()
    let viewportSize = CGSize(width: 240.0, height: 180.0)
    let layout = try #require(ViewportLayout(scene: scene, size: viewportSize))
    let plan = ViewportIdentityPickRenderPlanBuilder().build(scene: scene, layout: layout)
    let renderer = try ViewportIdentityBufferRenderer()

    let firstBuffer = try renderer.render(plan: plan, viewportSize: viewportSize)
    let secondBuffer = try renderer.render(plan: plan, viewportSize: viewportSize)
    let firstMetrics = try #require(firstBuffer.renderMetrics)
    let secondMetrics = try #require(secondBuffer.renderMetrics)

    #expect(firstMetrics.encodedMeshPrimitiveCacheHitCount == 0)
    #expect(firstMetrics.encodedMeshPrimitiveCacheMissCount == 1)
    #expect(secondMetrics.encodedMeshPrimitiveCacheHitCount == 1)
    #expect(secondMetrics.encodedMeshPrimitiveCacheMissCount == 0)

    let resizedViewportSize = CGSize(width: 320.0, height: 180.0)
    let resizedLayout = try #require(ViewportLayout(scene: scene, size: resizedViewportSize))
    let resizedPlan = ViewportIdentityPickRenderPlanBuilder().build(
        scene: scene,
        layout: resizedLayout
    )
    let resizedBuffer = try renderer.render(plan: resizedPlan, viewportSize: resizedViewportSize)
    let resizedMetrics = try #require(resizedBuffer.renderMetrics)

    #expect(resizedMetrics.encodedMeshPrimitiveCacheHitCount == 0)
    #expect(resizedMetrics.encodedMeshPrimitiveCacheMissCount == 1)
}

@MainActor
@Test func viewportIdentityHitResolverDoesNotReuseIdentityBufferAcrossSelectionPolicies() throws {
    let scene = identityBufferGeneratedTopologyScene()
    let viewportSize = CGSize(width: 240.0, height: 180.0)
    let layout = try #require(ViewportLayout(scene: scene, size: viewportSize))
    let renderer = CountingIdentityBufferRenderer()
    let resolver = ViewportIdentityHitResolver(rendererFactory: { renderer })

    _ = resolver.hitTest(
        point: layout.project(Point3D(x: -0.018, y: 0.0, z: -0.018)),
        in: scene,
        layout: layout,
        selectionHitPolicy: .face
    )
    _ = resolver.hitTest(
        point: layout.project(Point3D(x: -0.018, y: 0.0, z: -0.018)),
        in: scene,
        layout: layout,
        selectionHitPolicy: .vertex
    )

    #expect(renderer.renderCount == 2)
}

@MainActor
@Test func viewportIdentityHitResolverFallbackHonorsSelectionPolicy() throws {
    let scene = identityBufferGeneratedTopologyScene()
    let viewportSize = CGSize(width: 240.0, height: 180.0)
    let layout = try #require(ViewportLayout(scene: scene, size: viewportSize))
    let resolver = ViewportIdentityHitResolver(rendererFactory: {
        throw ViewportIdentityBufferRendererError.deviceUnavailable
    })
    let samplePoint = layout.project(Point3D(x: -0.018, y: 0.0, z: -0.018))
    let faceComponentID = SelectionComponentID.generatedTopology(
        "feature:body:subshape:identity:face:front"
    )
    let vertexComponentID = SelectionComponentID.generatedTopology(
        "feature:body:subshape:identity:vertex:frontBottomLeft"
    )

    let faceHit = resolver.hitTest(
        point: samplePoint,
        in: scene,
        layout: layout,
        selectionHitPolicy: .face
    )
    let vertexHit = resolver.hitTest(
        point: samplePoint,
        in: scene,
        layout: layout,
        selectionHitPolicy: .vertex
    )
    let objectHit = resolver.hitTest(
        point: samplePoint,
        in: scene,
        layout: layout,
        selectionHitPolicy: .object
    )

    #expect(faceHit?.pickingBackend == .projectedCPU)
    #expect(faceHit?.selectionComponent == .face(faceComponentID))
    #expect(vertexHit?.selectionComponent == .vertex(vertexComponentID))
    #expect(objectHit?.kind == .body)
    #expect(objectHit?.selectionComponent == nil)
    #expect(resolver.lastResolutionStatus == .fellBackAfterRendererUnavailable)
}

@MainActor
@Test func viewportIdentityHitResolverReturnsIdentityBufferGeneratedTopologyHit() throws {
    let scene = identityBufferGeneratedTopologyScene()
    let viewportSize = CGSize(width: 240.0, height: 180.0)
    let layout = try #require(ViewportLayout(scene: scene, size: viewportSize))
    let resolver = ViewportIdentityHitResolver()
    let faceComponentID = SelectionComponentID.generatedTopology(
        "feature:body:subshape:identity:face:front"
    )

    let hit = resolver.hitTest(
        point: layout.project(Point3D(x: 0.0, y: 0.0, z: 0.0)),
        in: scene,
        layout: layout
    )

    #expect(hit?.pickingBackend == .identityBuffer)
    #expect(hit?.selectionComponent == .face(faceComponentID))
    #expect(resolver.lastResolutionStatus == .renderedIdentityBuffer)
}

@MainActor
@Test func viewportIdentityHitResolverFallsBackToProjectedCPUWhenRendererIsUnavailable() throws {
    let scene = identityBufferGeneratedTopologyScene()
    let viewportSize = CGSize(width: 240.0, height: 180.0)
    let layout = try #require(ViewportLayout(scene: scene, size: viewportSize))
    let resolver = ViewportIdentityHitResolver(rendererFactory: {
        throw ViewportIdentityBufferRendererError.deviceUnavailable
    })
    let faceComponentID = SelectionComponentID.generatedTopology(
        "feature:body:subshape:identity:face:front"
    )

    let hit = resolver.hitTest(
        point: layout.project(Point3D(x: 0.0, y: 0.0, z: 0.0)),
        in: scene,
        layout: layout
    )

    #expect(hit?.pickingBackend == .projectedCPU)
    #expect(hit?.selectionComponent == .face(faceComponentID))
    #expect(resolver.lastResolutionStatus == .fellBackAfterRendererUnavailable)
}

@MainActor
@Test func viewportIdentityHitResolverRecordsRendererFailureFallback() throws {
    let scene = identityBufferGeneratedTopologyScene()
    let viewportSize = CGSize(width: 240.0, height: 180.0)
    let layout = try #require(ViewportLayout(scene: scene, size: viewportSize))
    let resolver = ViewportIdentityHitResolver(rendererFactory: {
        throw ViewportIdentityBufferRendererError.commandQueueCreationFailed
    })

    let hit = resolver.hitTest(
        point: layout.project(Point3D(x: 0.0, y: 0.0, z: 0.0)),
        in: scene,
        layout: layout
    )

    #expect(hit?.pickingBackend == .projectedCPU)
    #expect(resolver.lastResolutionStatus == .fellBackAfterRendererFailure)
}

@Test func viewportIdentityBufferReturnsSelectionHitsInsideRectangle() throws {
    let scene = identityBufferGeneratedTopologyScene()
    let viewportSize = CGSize(width: 240.0, height: 180.0)
    let layout = try #require(ViewportLayout(scene: scene, size: viewportSize))
    let plan = ViewportIdentityPickRenderPlanBuilder().build(scene: scene, layout: layout)
    let renderer = try ViewportIdentityBufferRenderer()
    let faceComponentID = SelectionComponentID.generatedTopology(
        "feature:body:subshape:identity:face:front"
    )
    let edgeComponentID = SelectionComponentID.generatedTopology(
        "feature:body:subshape:identity:edge:frontBottom"
    )
    let vertexComponentID = SelectionComponentID.generatedTopology(
        "feature:body:subshape:identity:vertex:frontBottomLeft"
    )

    let buffer = try renderer.render(plan: plan, viewportSize: viewportSize)
    let hits = buffer.hits(
        in: CGRect(
            x: 0.0,
            y: 0.0,
            width: viewportSize.width,
            height: viewportSize.height
        )
    )

    #expect(hits.contains {
        $0.pickingBackend == .identityBuffer && $0.selectionComponent == .face(faceComponentID)
    })
    #expect(hits.contains {
        $0.pickingBackend == .identityBuffer && $0.selectionComponent == .edge(edgeComponentID)
    })
    #expect(hits.contains {
        $0.pickingBackend == .identityBuffer && $0.selectionComponent == .vertex(vertexComponentID)
    })
}

@MainActor
@Test func viewportIdentityHitResolverReturnsIdentityBufferSelectionHits() throws {
    let scene = identityBufferGeneratedTopologyScene()
    let viewportSize = CGSize(width: 240.0, height: 180.0)
    let layout = try #require(ViewportLayout(scene: scene, size: viewportSize))
    let resolver = ViewportIdentityHitResolver()
    let vertexComponentID = SelectionComponentID.generatedTopology(
        "feature:body:subshape:identity:vertex:frontBottomLeft"
    )

    let hits = resolver.selectionHits(
        in: CGRect(x: 0.0, y: 0.0, width: viewportSize.width, height: viewportSize.height),
        scene: scene,
        layout: layout
    )

    #expect(hits.contains { $0.pickingBackend == .identityBuffer })
    #expect(hits.contains { $0.selectionComponent == .vertex(vertexComponentID) })
}

@MainActor
@Test func viewportIdentityHitResolverSelectionHitsHonorSelectionPolicy() throws {
    let scene = identityBufferGeneratedTopologyScene()
    let viewportSize = CGSize(width: 240.0, height: 180.0)
    let layout = try #require(ViewportLayout(scene: scene, size: viewportSize))
    let resolver = ViewportIdentityHitResolver()
    let selectionRect = CGRect(x: 0.0, y: 0.0, width: viewportSize.width, height: viewportSize.height)
    let faceComponentID = SelectionComponentID.generatedTopology(
        "feature:body:subshape:identity:face:front"
    )
    let edgeComponentID = SelectionComponentID.generatedTopology(
        "feature:body:subshape:identity:edge:frontBottom"
    )
    let vertexComponentID = SelectionComponentID.generatedTopology(
        "feature:body:subshape:identity:vertex:frontBottomLeft"
    )

    let faceHits = resolver.selectionHits(
        in: selectionRect,
        scene: scene,
        layout: layout,
        selectionHitPolicy: .face
    )
    let objectHits = resolver.selectionHits(
        in: selectionRect,
        scene: scene,
        layout: layout,
        selectionHitPolicy: .object
    )

    #expect(faceHits.contains { $0.selectionComponent == .face(faceComponentID) })
    #expect(faceHits.contains { $0.selectionComponent == .edge(edgeComponentID) } == false)
    #expect(faceHits.contains { $0.selectionComponent == .vertex(vertexComponentID) } == false)
    #expect(faceHits.contains { $0.kind == .body && $0.selectionComponent == nil } == false)
    #expect(objectHits.contains { $0.kind == .body && $0.selectionComponent == nil })
    #expect(objectHits.contains { $0.selectionComponent == .face(faceComponentID) } == false)
    #expect(objectHits.contains { $0.selectionComponent == .edge(edgeComponentID) } == false)
    #expect(objectHits.contains { $0.selectionComponent == .vertex(vertexComponentID) } == false)
}

@MainActor
@Test func viewportIdentityHitResolverReusesIdentityBufferForPointAndRectangleHits() throws {
    let scene = identityBufferGeneratedTopologyScene()
    let viewportSize = CGSize(width: 240.0, height: 180.0)
    let layout = try #require(ViewportLayout(scene: scene, size: viewportSize))
    let renderer = CountingIdentityBufferRenderer()
    let resolver = ViewportIdentityHitResolver(rendererFactory: { renderer })

    _ = resolver.hitTest(
        point: layout.project(Point3D(x: 0.0, y: 0.0, z: 0.0)),
        in: scene,
        layout: layout
    )
    _ = resolver.selectionHits(
        in: CGRect(x: 0.0, y: 0.0, width: viewportSize.width, height: viewportSize.height),
        scene: scene,
        layout: layout
    )

    #expect(renderer.renderCount == 1)
    #expect(resolver.lastRenderMetrics == renderer.lastRenderMetrics)
    #expect(resolver.lastResolutionStatus == .reusedIdentityBuffer)
    #expect(resolver.lastResolutionSummary?.renderMetrics == renderer.lastRenderMetrics)
}

@MainActor
@Test func viewportIdentityHitResolverDoesNotReuseIdentityBufferAcrossSketchPolicies() throws {
    let scene = try identityBufferSplineScene()
    let viewportSize = CGSize(width: 240.0, height: 180.0)
    let layout = try #require(ViewportLayout(scene: scene, size: viewportSize))
    let renderer = CountingIdentityBufferRenderer()
    let resolver = ViewportIdentityHitResolver(rendererFactory: { renderer })

    _ = resolver.selectionHits(
        in: CGRect(x: 0.0, y: 0.0, width: viewportSize.width, height: viewportSize.height),
        scene: scene,
        layout: layout,
        sketchControlPointHitPolicy: .none
    )
    _ = resolver.selectionHits(
        in: CGRect(x: 0.0, y: 0.0, width: viewportSize.width, height: viewportSize.height),
        scene: scene,
        layout: layout,
        sketchControlPointHitPolicy: .all
    )

    let recordCounts = renderer.renderedRecordCounts
    #expect(renderer.renderCount == 2)
    #expect(recordCounts.count == 2)
    if recordCounts.count == 2 {
        #expect(recordCounts[0] < recordCounts[1])
    }
}

@MainActor
@Test func viewportIdentityHitResolverInvalidateDropsCachedIdentityBuffer() throws {
    let scene = identityBufferGeneratedTopologyScene()
    let viewportSize = CGSize(width: 240.0, height: 180.0)
    let layout = try #require(ViewportLayout(scene: scene, size: viewportSize))
    let renderer = CountingIdentityBufferRenderer()
    let resolver = ViewportIdentityHitResolver(rendererFactory: { renderer })
    let selectionRect = CGRect(x: 0.0, y: 0.0, width: viewportSize.width, height: viewportSize.height)

    _ = resolver.selectionHits(in: selectionRect, scene: scene, layout: layout)
    _ = resolver.selectionHits(in: selectionRect, scene: scene, layout: layout)
    resolver.invalidate()
    _ = resolver.selectionHits(in: selectionRect, scene: scene, layout: layout)

    #expect(renderer.renderCount == 2)
    #expect(resolver.lastRenderMetrics == renderer.lastRenderMetrics)
    #expect(resolver.lastResolutionStatus == .renderedIdentityBuffer)
}

@MainActor
@Test func viewportIdentityHitResolverInvalidateClearsLastRenderMetrics() throws {
    let scene = identityBufferGeneratedTopologyScene()
    let viewportSize = CGSize(width: 240.0, height: 180.0)
    let layout = try #require(ViewportLayout(scene: scene, size: viewportSize))
    let renderer = CountingIdentityBufferRenderer()
    let resolver = ViewportIdentityHitResolver(rendererFactory: { renderer })
    let selectionRect = CGRect(x: 0.0, y: 0.0, width: viewportSize.width, height: viewportSize.height)

    _ = resolver.selectionHits(in: selectionRect, scene: scene, layout: layout)
    #expect(resolver.lastRenderMetrics != nil)

    resolver.invalidate()

    #expect(resolver.lastRenderMetrics == nil)
    #expect(resolver.lastResolutionSummary == nil)
}

@MainActor
@Test func viewportIdentityHitResolverFallsBackBeforeRenderingWhenPixelBudgetIsExceeded() throws {
    let scene = identityBufferGeneratedTopologyScene()
    let viewportSize = CGSize(width: 240.0, height: 180.0)
    let layout = try #require(ViewportLayout(scene: scene, size: viewportSize))
    let renderer = CountingIdentityBufferRenderer()
    let resolver = ViewportIdentityHitResolver(
        rendererFactory: { renderer },
        renderBudget: ViewportIdentityHitResolver.RenderBudget(
            maximumPixelCount: 1,
            maximumDrawItemCount: 200_000,
            maximumEncodedPointCount: 1_000_000
        )
    )
    let faceComponentID = SelectionComponentID.generatedTopology(
        "feature:body:subshape:identity:face:front"
    )

    let hit = resolver.hitTest(
        point: layout.project(Point3D(x: 0.0, y: 0.0, z: 0.0)),
        in: scene,
        layout: layout
    )

    #expect(renderer.renderCount == 0)
    #expect(resolver.lastBudgetRejection?.limit == .pixelCount)
    #expect(resolver.lastRenderCost?.pixelCount == 43_200)
    #expect(resolver.lastRenderMetrics == nil)
    #expect(resolver.lastResolutionStatus == .fellBackAfterBudgetRejection)
    #expect(resolver.lastResolutionSummary?.budgetRejection?.limit == .pixelCount)
    #expect(hit?.pickingBackend == .projectedCPU)
    #expect(hit?.selectionComponent == .face(faceComponentID))
}

@MainActor
@Test func viewportIdentityHitResolverFallsBackBeforeRenderingWhenPlanBudgetIsExceeded() throws {
    let scene = identityBufferGeneratedTopologyScene()
    let viewportSize = CGSize(width: 240.0, height: 180.0)
    let layout = try #require(ViewportLayout(scene: scene, size: viewportSize))
    let renderer = CountingIdentityBufferRenderer()
    let resolver = ViewportIdentityHitResolver(
        rendererFactory: { renderer },
        renderBudget: ViewportIdentityHitResolver.RenderBudget(
            maximumPixelCount: 8_294_400,
            maximumDrawItemCount: 1,
            maximumEncodedPointCount: 1_000_000
        )
    )

    let hits = resolver.selectionHits(
        in: CGRect(x: 0.0, y: 0.0, width: viewportSize.width, height: viewportSize.height),
        scene: scene,
        layout: layout
    )

    #expect(renderer.renderCount == 0)
    #expect(resolver.lastBudgetRejection?.limit == .drawItemCount)
    #expect((resolver.lastRenderCost?.drawItemCount ?? 0) > 1)
    #expect(resolver.lastResolutionStatus == .fellBackAfterBudgetRejection)
    #expect(hits.contains { $0.pickingBackend == .projectedCPU })
}

@MainActor
@Test func viewportIdentityHitResolverFallsBackBeforeRenderingWhenEncodedPointBudgetIsExceeded() throws {
    let scene = identityBufferGeneratedTopologyScene()
    let viewportSize = CGSize(width: 240.0, height: 180.0)
    let layout = try #require(ViewportLayout(scene: scene, size: viewportSize))
    let renderer = CountingIdentityBufferRenderer()
    let resolver = ViewportIdentityHitResolver(
        rendererFactory: { renderer },
        renderBudget: ViewportIdentityHitResolver.RenderBudget(
            maximumPixelCount: 8_294_400,
            maximumDrawItemCount: 200_000,
            maximumEncodedPointCount: 1
        )
    )

    let hits = resolver.selectionHits(
        in: CGRect(x: 0.0, y: 0.0, width: viewportSize.width, height: viewportSize.height),
        scene: scene,
        layout: layout
    )

    #expect(renderer.renderCount == 0)
    #expect(resolver.lastBudgetRejection?.limit == .encodedPointCount)
    #expect((resolver.lastRenderCost?.encodedPointCount ?? 0) > 1)
    #expect(resolver.lastResolutionStatus == .fellBackAfterBudgetRejection)
    #expect(hits.contains { $0.pickingBackend == .projectedCPU })
}

@MainActor
@Test func viewportIdentityHitResolverDoesNotCacheMismatchedRenderedBuffer() throws {
    let scene = identityBufferGeneratedTopologyScene()
    let viewportSize = CGSize(width: 240.0, height: 180.0)
    let layout = try #require(ViewportLayout(scene: scene, size: viewportSize))
    let renderer = MismatchedIdentityBufferRenderer()
    let resolver = ViewportIdentityHitResolver(rendererFactory: { renderer })
    let point = layout.project(Point3D(x: 0.0, y: 0.0, z: 0.0))

    _ = resolver.hitTest(point: point, in: scene, layout: layout)
    _ = resolver.hitTest(point: point, in: scene, layout: layout)

    #expect(renderer.renderCount == 2)
    #expect(resolver.lastRenderMetrics == nil)
    #expect(resolver.lastResolutionStatus == .fellBackAfterInvalidRenderedBuffer)
}

@MainActor
@Test func viewportIdentityHitResolverSelectionFallsBackToProjectedCPUWhenRendererIsUnavailable() throws {
    let scene = identityBufferGeneratedTopologyScene()
    let viewportSize = CGSize(width: 240.0, height: 180.0)
    let layout = try #require(ViewportLayout(scene: scene, size: viewportSize))
    let resolver = ViewportIdentityHitResolver(rendererFactory: {
        throw ViewportIdentityBufferRendererError.deviceUnavailable
    })
    let vertexComponentID = SelectionComponentID.generatedTopology(
        "feature:body:subshape:identity:vertex:frontBottomLeft"
    )

    let hits = resolver.selectionHits(
        in: CGRect(x: 0.0, y: 0.0, width: viewportSize.width, height: viewportSize.height),
        scene: scene,
        layout: layout
    )

    #expect(hits.contains { $0.pickingBackend == .projectedCPU })
    #expect(hits.contains { $0.selectionComponent == .vertex(vertexComponentID) })
    #expect(resolver.lastResolutionStatus == .fellBackAfterRendererUnavailable)
}

@MainActor
@Test func viewportIdentityHitResolverSelectionHonorsSketchControlPointPolicy() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createSplineSketch(
            name: "Viewport Identity Rectangle Spline Policy",
            plane: .xy,
            spline: SketchSpline(controlPoints: [
                SketchPoint(x: .length(0.0, .millimeter), y: .length(0.0, .millimeter)),
                SketchPoint(x: .length(2.0, .millimeter), y: .length(4.0, .millimeter)),
                SketchPoint(x: .length(6.0, .millimeter), y: .length(4.0, .millimeter)),
                SketchPoint(x: .length(8.0, .millimeter), y: .length(0.0, .millimeter)),
            ])
        )
    )
    let scene = ViewportSceneBuilder().build(document: session.document)
    let viewportSize = CGSize(width: 240.0, height: 180.0)
    let layout = try #require(ViewportLayout(scene: scene, size: viewportSize))
    let resolver = ViewportIdentityHitResolver()

    let hiddenHits = resolver.selectionHits(
        in: CGRect(x: 0.0, y: 0.0, width: viewportSize.width, height: viewportSize.height),
        scene: scene,
        layout: layout,
        sketchControlPointHitPolicy: .none
    )
    let visibleHits = resolver.selectionHits(
        in: CGRect(x: 0.0, y: 0.0, width: viewportSize.width, height: viewportSize.height),
        scene: scene,
        layout: layout,
        sketchControlPointHitPolicy: .all
    )

    #expect(hiddenHits.contains { $0.sketchControlPointIndex != nil } == false)
    #expect(visibleHits.contains { $0.sketchControlPointIndex == 1 })
}

@MainActor
@Test func viewportIdentityBufferRendererSamplesProjectedBodyFallbackHits() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let scene = ViewportSceneBuilder().build(document: session.document)
    let viewportSize = CGSize(width: 240.0, height: 180.0)
    let layout = try #require(ViewportLayout(scene: scene, size: viewportSize))
    let bodyItem = try #require(scene.items.first { item in
        if case .body = item.kind {
            return true
        }
        return false
    })
    let projection = try #require(layout.bodyProjection(for: bodyItem))
    let plan = ViewportIdentityPickRenderPlanBuilder().build(scene: scene, layout: layout)
    let renderer = try ViewportIdentityBufferRenderer()

    let vertexSample = try renderer.sample(
        point: projection.point(for: .backTopRight),
        plan: plan,
        viewportSize: viewportSize
    )

    #expect(vertexSample.rawValue != ViewportPickIdentity.backgroundRawValue)
    #expect(vertexSample.hit?.pickingBackend == .identityBuffer)
    #expect(vertexSample.hit?.bodyVertex == .backTopRight)
}

private func identityBufferGeneratedTopologyScene(
    origin: Point3D = .origin
) -> ViewportScene {
    let featureID = FeatureID()
    let faceComponentID = SelectionComponentID.generatedTopology(
        "feature:body:subshape:identity:face:front"
    )
    let edgeComponentID = SelectionComponentID.generatedTopology(
        "feature:body:subshape:identity:edge:frontBottom"
    )
    let vertexComponentID = SelectionComponentID.generatedTopology(
        "feature:body:subshape:identity:vertex:frontBottomLeft"
    )
    let frontBottomLeft = Point3D(
        x: origin.x - 0.020,
        y: origin.y,
        z: origin.z - 0.020
    )
    let frontBottomRight = Point3D(
        x: origin.x + 0.020,
        y: origin.y,
        z: origin.z - 0.020
    )
    let frontTopRight = Point3D(
        x: origin.x + 0.020,
        y: origin.y,
        z: origin.z + 0.020
    )
    let frontTopLeft = Point3D(
        x: origin.x - 0.020,
        y: origin.y,
        z: origin.z + 0.020
    )
    let topology = ViewportBodyTopology(
        faces: [
            ViewportBodyTopology.Face(
                componentID: faceComponentID,
                points: [
                    frontBottomLeft,
                    frontBottomRight,
                    frontTopRight,
                    frontTopLeft,
                ]
            ),
        ],
        edges: [
            ViewportBodyTopology.Edge(
                componentID: edgeComponentID,
                start: frontBottomLeft,
                end: frontBottomRight
            ),
        ],
        vertices: [
            ViewportBodyTopology.Vertex(
                componentID: vertexComponentID,
                point: frontBottomLeft
            ),
        ]
    )
    let component = ViewportBodyComponent(
        sizeXMeters: 0.040,
        sizeYMeters: 0.020,
        sizeZMeters: 0.040,
        yMinMeters: origin.y,
        yMaxMeters: origin.y + 0.020,
        topology: topology
    )
    let item = ViewportSceneItem(
        id: featureID.description,
        featureID: featureID,
        modelBounds: CGRect(
            x: CGFloat(origin.x - 0.020),
            y: CGFloat(origin.z - 0.020),
            width: 0.040,
            height: 0.040
        ),
        kind: .body(component: component)
    )
    return ViewportScene(items: [item])
}

private func identityPlanPoints(_ plan: ViewportIdentityPickRenderPlan) -> [CGPoint] {
    plan.drawItems.flatMap { item in
        switch item.primitive {
        case .polygon(let points):
            return points
        case .polyline(let points, _, _):
            return points
        case .segment(let start, let end, _):
            return [start, end]
        case .point(let center, _):
            return [center]
        }
    }
}

private func identityBufferMeshFallbackScene() -> ViewportScene {
    let mesh = ViewportBodyMesh(
        positions: [
            Point3D(x: -0.010, y: 0.0, z: -0.010),
            Point3D(x: 0.010, y: 0.0, z: -0.010),
            Point3D(x: 0.0, y: 0.0, z: 0.010),
        ],
        indices: [0, 1, 2]
    )
    let component = ViewportBodyComponent(
        sizeXMeters: 0.020,
        sizeYMeters: 0.001,
        sizeZMeters: 0.020,
        yMinMeters: 0.0,
        yMaxMeters: 0.001,
        mesh: mesh
    )
    let featureID = FeatureID()
    let item = ViewportSceneItem(
        id: featureID.description,
        featureID: featureID,
        modelBounds: CGRect(x: -0.010, y: -0.010, width: 0.020, height: 0.020),
        kind: .body(component: component)
    )
    return ViewportScene(items: [item])
}

@MainActor
private func identityBufferSplineScene() throws -> ViewportScene {
    let session = EditorSession()
    _ = try session.execute(
        .createSplineSketch(
            name: "Viewport Identity Cache Spline",
            plane: .xy,
            spline: SketchSpline(controlPoints: [
                SketchPoint(x: .length(0.0, .millimeter), y: .length(0.0, .millimeter)),
                SketchPoint(x: .length(2.0, .millimeter), y: .length(4.0, .millimeter)),
                SketchPoint(x: .length(6.0, .millimeter), y: .length(4.0, .millimeter)),
                SketchPoint(x: .length(8.0, .millimeter), y: .length(0.0, .millimeter)),
            ])
        )
    )
    return ViewportSceneBuilder().build(document: session.document)
}

private final class CountingIdentityBufferRenderer: ViewportIdentityBufferRendering {
    private(set) var renderCount = 0
    private(set) var renderedRecordCounts: [Int] = []
    private(set) var lastRenderMetrics: ViewportIdentityBufferRenderMetrics?

    func render(
        plan: ViewportIdentityPickRenderPlan,
        viewportSize: CGSize
    ) throws -> ViewportIdentityBuffer {
        guard viewportSize.width.isFinite,
              viewportSize.height.isFinite,
              viewportSize.width > 0.0,
              viewportSize.height > 0.0 else {
            throw ViewportIdentityBufferRendererError.invalidViewportSize
        }
        renderCount += 1
        renderedRecordCounts.append(plan.index.count)

        let width = max(Int(ceil(viewportSize.width)), 1)
        let height = max(Int(ceil(viewportSize.height)), 1)
        let rawValue = plan.index.records.first?.identity.rawValue
            ?? ViewportPickIdentity.backgroundRawValue
        let metrics = ViewportIdentityBufferRenderMetrics(
            viewportWidth: width,
            viewportHeight: height,
            encodedCommandCount: plan.drawItems.count,
            encodedPointCount: plan.drawItems.reduce(0) { partialResult, item in
                partialResult + item.primitive.encodedPointCount
            },
            pixelCount: width * height,
            encodeDurationSeconds: Double(renderCount) * 0.001,
            gpuDurationSeconds: Double(renderCount) * 0.002,
            readbackDurationSeconds: Double(renderCount) * 0.003,
            totalDurationSeconds: Double(renderCount) * 0.006
        )
        lastRenderMetrics = metrics
        return ViewportIdentityBuffer(
            width: width,
            height: height,
            rawValues: Array(repeating: rawValue, count: width * height),
            index: plan.index,
            renderMetrics: metrics
        )
    }
}

private final class MismatchedIdentityBufferRenderer: ViewportIdentityBufferRendering {
    private(set) var renderCount = 0

    func render(
        plan: ViewportIdentityPickRenderPlan,
        viewportSize: CGSize
    ) throws -> ViewportIdentityBuffer {
        renderCount += 1
        return ViewportIdentityBuffer(
            width: 1,
            height: 1,
            rawValues: [ViewportPickIdentity.backgroundRawValue],
            index: plan.index
        )
    }
}
