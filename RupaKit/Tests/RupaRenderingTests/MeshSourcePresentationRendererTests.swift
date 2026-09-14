import Foundation
import CoreGraphics
import Metal
import RealityKit
import Synchronization
import RupaCore
import RupaCoreTypes
import RupaEvaluation
import RupaProjectModel
import RupaResponsivenessBaseline
import RupaViewportScene
import SwiftCAD
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
func presentationPlanAdmissionIncludesNativeAdapterInputBuffers() throws {
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
        2 * 3 * MemoryLayout<UInt32>.stride
        + 6 * MemoryLayout<UInt32>.stride
        + MemoryLayout<MeshFaceID>.stride
        + MemoryLayout<SIMD3<Float>>.stride
        + 6 * MemoryLayout<UInt32>.stride
    #expect(
        trianglePlan.retainedByteCount - pointPlan.retainedByteCount
            == expectedTriangleAndBoundaryBytes
    )

    let expectedPositionBytes = 3 * (
        MemoryLayout<GeometryPoint3D>.stride
            + MemoryLayout<MeshVertexID>.stride
            + MemoryLayout<SIMD3<Float>>.stride
    )
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
            == expectedItemBytes + expectedPositionBytes
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
func presentationPlanMemoryCeilingIncludesScratchAndAdapterInputs() throws {
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
func meshSourcePresentationRenderPlanConsumesCADOnlyThroughItsOwnTraversal() throws {
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
    let plan = try MeshSourcePresentationRenderPlan(scene: scene)

    #expect(plan.itemCount == 1)
    #expect(plan.triangleCount == 2)
    var emittedCount = 0
    var cadCount = 0
    var sawTranslatedOrigin = false
    var sawTranslatedOppositeCorner = false
    plan.forEachTriangle { triangle in
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
func meshSourcePresentationRenderPlanConsumesMeshOnlyThroughTheSameTraversal() throws {
    let sourceReference = GeometrySourceReference.authoredMesh(
        GeometrySourceID(rawValue: "mesh.presentation")
    )
    let (scene, _) = try presentationScene(
        references: [sourceReference],
        transforms: [.identity]
    )
    let plan = try MeshSourcePresentationRenderPlan(scene: scene)

    var emittedCount = 0
    var meshCount = 0
    var vertexIDSum: UInt64 = 0
    plan.forEachTriangle { triangle in
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
func meshSourcePresentationRenderPlanUsesGeometryEarClippingForConcaveFaces() throws {
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
    let plan = try MeshSourcePresentationRenderPlan(scene: scene)

    var actualKeys: Set<String> = []
    var triangleArea = 0.0
    var emittedCount = 0
    plan.forEachTriangle { triangle in
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
    plan.forEachTriangle { _ in
        secondPassCount += 1
    }
    #expect(secondPassCount == emittedCount)
}

@Test(.timeLimit(.minutes(1)))
func meshSourcePresentationRenderPlanConsumesMixedSelectionsAndReusesSnapshotPlan() throws {
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
    let plan = try MeshSourcePresentationRenderPlan(scene: scene)
    let initialSourceChunkIdentities = sourceChunkIdentitySummary(source)

    var firstPassCount = 0
    var firstPassCadCount = 0
    var firstPassMeshCount = 0
    var firstPassPositionSum = GeometryPoint3D(x: 0, y: 0, z: 0)
    plan.forEachTriangle { triangle in
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
    plan.forEachTriangle { triangle in
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
func meshSourcePresentationRenderPlanRejectsAuthorityAndBufferFailuresAsTypedErrors() throws {
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
func meshSourcePresentationRenderPlanMapsGeometryTriangulationFailures() throws {
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
func meshSourcePresentationRenderPlanMapsFaceRangeArithmeticOverflow() throws {
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
func meshSourcePresentationRenderPlanReportsTransformFailureDuringConstruction() throws {
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
        _ = try MeshSourcePresentationRenderPlan(scene: invalidTransformScene)
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
    let plan = try MeshSourcePresentationRenderPlan(scene: scene)
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
    plan.forEachTriangle { triangle in
        emittedCount += 1
        #expect(triangle.sourceReference == sourceReference)
    }
    #expect(emittedCount == 4 * segmentCount - 4)
}

@Test(.timeLimit(.minutes(2)))
func realityViewportPreparesDenseSingleOccurrenceUpload() async throws {
    let segmentCount = 6_284
    let cylinderCount = 4
    let source = try presentationHighSegmentCylinderSource(segmentCount: segmentCount, cylinderCount: cylinderCount)
    let sourceReference = GeometrySourceReference.authoredMesh(source.identity)
    let scene = try presentationScene(
        source: source,
        references: [sourceReference],
        transforms: [.identity]
    ).scene

    // Plan construction is deliberately detached from the MainActor. Only
    // RealityKit native resource construction is allowed to cross back to the
    // RealityViewport MainActor owner.
    let plan = try await Task.detached(priority: .userInitiated) {
        try MeshSourcePresentationRenderPlan(scene: scene)
    }.value

    let expectedPositionCount = cylinderCount * 2 * segmentCount
    let expectedTriangleCount = cylinderCount * (4 * segmentCount - 4)
    #expect(plan.itemCount == 1)
    #expect(source.vertexIDs.count == expectedPositionCount)
    #expect(source.faceIDs.count == cylinderCount * (segmentCount + 2))
    #expect(plan.positionCount == expectedPositionCount)
    #expect(plan.triangleCount == expectedTriangleCount)
    #expect(plan.positionCount <= MeshSourcePresentationPlanLimits.standard.maxPositionCount)
    #expect(plan.triangleCount <= MeshSourcePresentationPlanLimits.standard.maxTriangleCount)
    #expect(plan.workingByteCount <= MeshSourcePresentationPlanLimits.standard.maxRetainedByteCount)

    print(
        "RealityViewport dense fixture: "
            + "cylinders=\(cylinderCount), segments=\(segmentCount), "
            + "items=\(plan.itemCount), positions=\(plan.positionCount), "
            + "triangles=\(plan.triangleCount), retainedBytes=\(plan.retainedByteCount), "
            + "workingBytes=\(plan.workingByteCount), "
            + "processNativePeakBytes=unmeasured(separate signed-App gate)"
    )

    let overBudgetSource = try presentationHighSegmentCylinderSource(segmentCount: segmentCount, cylinderCount: 12)
    let overBudgetScene = try presentationScene(
        source: overBudgetSource,
        references: [.authoredMesh(overBudgetSource.identity)],
        transforms: [.identity]
    ).scene
    var overBudgetError: MeshSourcePresentationRenderError?
    do {
        _ = try MeshSourcePresentationRenderPlan(scene: overBudgetScene)
    } catch let error as MeshSourcePresentationRenderError {
        overBudgetError = error
    }
    #expect(overBudgetError?.code == .resourceExhausted)

    let viewport = try await RealityViewport.prepare(plan: plan)
    let halfFrameBudget = Duration.microseconds(8_333)
    let uploadDuration = await viewport.maximumNativeUploadDuration
    print(
        "RealityViewport native LowLevelMesh upload: "
            + "duration=\(uploadDuration), budget=\(halfFrameBudget), "
            + "deviceSpecific=true"
    )
    #expect(
        uploadDuration <= halfFrameBudget,
        "Native LowLevelMesh upload exceeded the device-specific 60 Hz half-frame budget."
    )
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func realityViewportSharesTranslatedResourcesWithoutSharingOccurrenceIdentity() async throws {
    let source = try presentationQuadSource()
    let reference = GeometrySourceReference.authoredMesh(source.identity)
    let shear = try GeometryTransform3D(values: [
        1, 1, 0, 6,
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1,
    ])
    let scene = try presentationScene(
        source: source, references: [reference, reference, reference, reference],
        transforms: [.identity, translationTransform(x: 2, y: 0, z: 0), shear,
                     translationTransform(x: 0, y: 0, z: 1)]
    ).scene
    let plan = try MeshSourcePresentationRenderPlan(scene: scene)
    let viewport = try await RealityViewport.prepare(plan: plan)
    let renderer = try RealityRenderer()
    renderer.cameraSettings.colorBackground = .color(CGColor(gray: 0, alpha: 1))
    renderer.cameraSettings.isToneMappingEnabled = false
    renderer.entities.append(viewport.root)
    renderer.activeCamera = viewport.camera
    let layout = ViewportLayout(
        modelBounds: CGRect(x: 0, y: 0, width: 8, height: 1), size: CGSize(width: 640, height: 128),
        camera: .init(zoom: 0.8), basis: .axisFront(.z), verticalBounds: 0...1
    )
    try viewport.applyCamera(layout: layout, displayScale: 2, revision: 1)
    let colors = [ColorRGBA(r: 1, g: 0, b: 0, a: 1), ColorRGBA(r: 0, g: 0, b: 1, a: 1),
                  ColorRGBA(r: 0, g: 1, b: 0, a: 1), ColorRGBA(r: 1, g: 0, b: 0, a: 1)]
    var materialColors: [SceneOccurrenceID: ColorRGBA] = [:]
    for index in scene.items.indices { materialColors[scene.items[index].id] = colors[index] }
    try viewport.applyAppearance(
        displayMode: .solidWithEdges, shading: .init(style: .flat, solidColor: .material),
        materialColors: materialColors,
        interaction: .init(sceneNodeIDByOccurrenceID: [:], selectedSceneNodeIDs: [],
                           previewSceneNodeIDs: [], hoveredSceneNodeID: nil),
        sectionPlane: nil, retainedSide: .front, sectionTolerance: 0
    )
    let device = try #require(MTLCreateSystemDefaultDevice())
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .bgra8Unorm, width: 640, height: 128, mipmapped: false
    )
    descriptor.storageMode = .shared
    descriptor.usage = [.renderTarget, .shaderRead, .shaderWrite]
    let texture = try #require(device.makeTexture(descriptor: descriptor))
    let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))
    func render() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                try renderer.updateAndRender(deltaTime: 1 / 60, cameraOutput: output,
                                             onComplete: { _ in continuation.resume() })
            } catch { continuation.resume(throwing: error) }
        }
    }
    try await render()
    let nativeScene = try #require(viewport.root.scene)
    var surfaces: [Entity] = []
    var meshes: [MeshResource] = []
    var shapes: [ShapeResource] = []
    for (index, x) in [Float(0.25), 2.25, 6.5].enumerated() {
        let hit = try #require(nativeScene.raycast(origin: [x, 0.25, 0.5], direction: [0, 0, -1], length: 1).first)
        let triangle = try #require(viewport.triangle(for: hit))
        #expect(triangle.occurrenceID == scene.items[index].id)
        #expect(triangle.faceID == source.faceIDs[0])
        #expect(abs(hit.position.x - x) < 0.0001)
        surfaces.append(hit.entity)
        meshes.append(try #require(hit.entity.components[ModelComponent.self]?.mesh))
        shapes.append(try #require(hit.entity.components[CollisionComponent.self]?.shapes.first))
        let projected = try #require(layout.projectedPoint(Point3D(x: Double(x), y: 0.25, z: 0))).point
        let pixelX = Int(projected.x.rounded()), pixelY = Int(projected.y.rounded())
        try #require((0..<640).contains(pixelX) && (0..<128).contains(pixelY))
        var pixel = [UInt8](repeating: 0, count: 4)
        texture.getBytes(&pixel, bytesPerRow: 4, from: MTLRegionMake2D(pixelX, pixelY, 1, 1), mipmapLevel: 0)
        let expectedChannel = [2, 0, 1][index]
        #expect(pixel[expectedChannel] > 200, "Distinct occurrence material rendered BGRA \(pixel)")
        for channel in 0..<3 where channel != expectedChannel {
            #expect(Int(pixel[expectedChannel]) - Int(pixel[channel]) > 100)
        }
    }
    #expect(surfaces[0] !== surfaces[1])
    #expect(meshes[0] === meshes[1])
    #expect(shapes[0] == shapes[1])
    #expect(meshes[0] !== meshes[2])
    #expect(shapes[0] != shapes[2])
    let parent = try #require(surfaces[0].parent)
    let lineMeshes = parent.children.compactMap { entity -> MeshResource? in
        guard entity.components[CollisionComponent.self] == nil else { return nil }
        return entity.components[ModelComponent.self]?.mesh
    }
    #expect(lineMeshes.count == 4)
    #expect(Set(lineMeshes.map(ObjectIdentifier.init)).count == 2)
    let section = SectionAnalysisResult.Plane(
        sourceKind: .sketchPlane, sourceID: nil, sourceName: nil,
        origin: Point3D(x: 1.5, y: 0, z: 0), normal: Vector3D(x: 1, y: 0, z: 0),
        u: Vector3D(x: 0, y: 1, z: 0), v: Vector3D(x: 0, y: 0, z: 1)
    )
    try viewport.applySection(plane: section, side: .front, tolerance: 0)
    let clipper = try #require(parent.parent)
    #expect(clipper.position == .zero && parent.position == .zero)
    #expect(clipper.scale == .one && parent.scale == .one)
    try await render()
    for (index, x) in [Float(0.25), 2.25].enumerated() {
        let hits = nativeScene.raycast(origin: [x, 0.25, 2], direction: [0, 0, -1], length: 3)
        #expect(viewport.retainedHits(hits, rayDirection: [0, 0, -1]).isEmpty == (index == 0))
        let projected = try #require(layout.projectedPoint(Point3D(x: Double(x), y: 0.25, z: 0))).point
        var pixel = [UInt8](repeating: 0, count: 4)
        texture.getBytes(&pixel, bytesPerRow: 4,
                         from: MTLRegionMake2D(Int(projected.x.rounded()), Int(projected.y.rounded()), 1, 1), mipmapLevel: 0)
        #expect(index == 0 ? pixel[2] < 20 : pixel[0] > 200)
    }
}

@Test(.timeLimit(.minutes(1)))
func realityViewportRefusesGroupingBeyondTheCallerByteLimit() async throws {
    let reference = GeometrySourceReference.authoredMesh(GeometrySourceID(rawValue: "mesh.presentation"))
    let scene = try presentationScene(references: Array(repeating: reference, count: 16),
                                      transforms: Array(repeating: .identity, count: 16)).scene
    let standard = try MeshSourcePresentationRenderPlan(scene: scene)
    let limits = MeshSourcePresentationPlanLimits(
        maxItemCount: 16, maxPositionCount: standard.positionCount,
        maxTriangleCount: standard.triangleCount, maxRetainedByteCount: standard.workingByteCount
    )
    let plan = try MeshSourcePresentationRenderPlan(scene: scene, planLimits: limits)
    do {
        _ = try await RealityViewport.prepare(plan: plan)
        Issue.record("Native grouping must respect the caller's lowered byte ceiling.")
    } catch let error as MeshSourcePresentationRenderError {
        #expect(error.code == .resourceExhausted)
    }
}

@Test(.timeLimit(.minutes(1)))
func realityViewportPreparesMaximumAdmittedNativeLineUpload() async throws {
    let hardMaximum = MeshSourcePresentationPlanLimits.hardMaximum
    let itemBytes = MemoryLayout<MeshSourcePresentationRenderPlan.Occurrence>.stride + 128
    let positionBytesPerVertex = MemoryLayout<GeometryPoint3D>.stride
        + MemoryLayout<MeshVertexID>.stride
        + MemoryLayout<SIMD3<Float>>.stride
    let retainedBytesPerTriangle = 4 * 3 * MemoryLayout<UInt32>.stride
        + MemoryLayout<MeshFaceID>.stride
        + MemoryLayout<SIMD3<Float>>.stride
        + 6 * MemoryLayout<UInt32>.stride
    let lineBytesPerVertex = MemoryLayout<SIMD3<Float>>.stride
    let lineBytesPerTriangle = 6 * MemoryLayout<UInt32>.stride
    let minimumIndexScratch = try MeshSourceTriangulationIndex.storageReservation(vertexCount: 3)
    let minimumFaceScratch = 3 * 256 + minimumIndexScratch
    let fixedWorkingBytes = itemBytes + minimumFaceScratch

    // Enumerate the complete admitted position range. The largest native line
    // payload is selected from the actual plan charge, not from a sample-size
    // fixture or an assumed allocator limit.
    var maximum: (positionCount: Int, triangleCount: Int, lineBytes: Int)?
    for positionCount in 3...hardMaximum.maxPositionCount {
        let triangulationReservation = try MeshSourceTriangulationIndex.storageReservation(
            vertexCount: positionCount
        )
        let fixedBytes = fixedWorkingBytes + positionBytesPerVertex * positionCount
            + triangulationReservation
        guard fixedBytes < hardMaximum.maxRetainedByteCount else { continue }
        let byteLimitedTriangles = (hardMaximum.maxRetainedByteCount - fixedBytes)
            / retainedBytesPerTriangle
        let triangleCount = min(hardMaximum.maxTriangleCount, byteLimitedTriangles)
        guard triangleCount > 0 else { continue }
        let lineBytes = lineBytesPerVertex * positionCount
            + lineBytesPerTriangle * triangleCount
        if maximum == nil || lineBytes > maximum!.lineBytes {
            maximum = (positionCount, triangleCount, lineBytes)
        }
    }
    let selected = try #require(maximum)
    #expect(selected.positionCount == 4)
    #expect(selected.triangleCount == 234_073)
    #expect(selected.lineBytes == 5_617_816)

    func makeRepeatedTriangleSource(triangleCount: Int) throws -> MeshSource {
        var builder = MeshSourceBuilder(identity: "mesh.presentation-maximum-line-upload")
        try builder.reserveCapacity(vertexCount: 4, faceCount: triangleCount, cornerCount: triangleCount * 3)
        let first = try builder.addVertex(GeometryPoint3D(x: 0, y: 0, z: 0))
        let second = try builder.addVertex(GeometryPoint3D(x: 1, y: 0, z: 0))
        let third = try builder.addVertex(GeometryPoint3D(x: 0, y: 1, z: 0))
        _ = try builder.addVertex(GeometryPoint3D(x: 0, y: 0, z: 1))
        for _ in 0..<triangleCount {
            _ = try builder.addTriangle(first, second, third)
        }
        return try builder.build()
    }

    let source = try makeRepeatedTriangleSource(triangleCount: selected.triangleCount)
    let fixture = try presentationScene(
        source: source,
        references: [.authoredMesh(source.identity)],
        transforms: [.identity]
    )
    let plan = try MeshSourcePresentationRenderPlan(scene: fixture.scene)
    let triangulationReservation = try MeshSourceTriangulationIndex.storageReservation(
        vertexCount: selected.positionCount
    )
    let expectedRetainedBytes = itemBytes
        + positionBytesPerVertex * selected.positionCount
        + retainedBytesPerTriangle * selected.triangleCount
    let expectedWorkingBytes = expectedRetainedBytes
        + triangulationReservation + minimumFaceScratch
    #expect(plan.positionCount == selected.positionCount)
    #expect(plan.triangleCount == selected.triangleCount)
    #expect(plan.boundaryIndexCount == selected.triangleCount * 6)
    #expect(plan.retainedByteCount == expectedRetainedBytes)
    #expect(plan.workingByteCount == expectedWorkingBytes)
    #expect(plan.retainedByteCount == 22_471_584)
    #expect(plan.workingByteCount == 22_473_120)

    do {
        let overBudgetSource = try makeRepeatedTriangleSource(triangleCount: selected.triangleCount + 1)
        let overBudgetScene = try presentationScene(
            source: overBudgetSource,
            references: [.authoredMesh(overBudgetSource.identity)],
            transforms: [.identity]
        ).scene
        var overBudgetError: MeshSourcePresentationRenderError?
        do {
            _ = try MeshSourcePresentationRenderPlan(scene: overBudgetScene)
        } catch let error as MeshSourcePresentationRenderError {
            overBudgetError = error
        }
        #expect(overBudgetError?.code == .resourceExhausted)
    }

    let baselineBytes = try ResponsivenessFootprintProbe.physicalFootprintBytes()
    // One millisecond is the established measurement resolution; sampled
    // process footprint is evidence for this run, not an opaque SDK bound.
    let sampler = ResponsivenessFootprintPeakSampler(intervalSeconds: 0.001)
    sampler.start()
    let viewport: RealityViewport
    do {
        viewport = try await RealityViewport.prepare(plan: plan)
    } catch {
        await sampler.stop()
        throw error
    }
    await sampler.stop()
    let retainedBytes = try ResponsivenessFootprintProbe.physicalFootprintBytes()
    let peak = try sampler.peakBytes()
    let baselineSigned = try #require(Int64(exactly: baselineBytes))
    let retainedSigned = try #require(Int64(exactly: retainedBytes))
    let peakSigned = try #require(Int64(exactly: peak.bytes))
    let signedRetainedDelta = retainedSigned - baselineSigned
    let signedPeakDelta = peakSigned - baselineSigned
    let uploadDuration = await viewport.maximumNativeUploadDuration
    let halfFrameBudget = Duration.microseconds(8_333)
    print("""
        RealityViewport maximum native line upload:
        P=\(plan.positionCount), T=\(plan.triangleCount), boundaryIndices=\(plan.boundaryIndexCount)
        lineBytes=\(selected.lineBytes), retained=\(plan.retainedByteCount), working=\(plan.workingByteCount)
        upload=\(uploadDuration), baselineFootprint=\(baselineBytes), peakFootprint=\(peak.bytes)
        retainedFootprint=\(retainedBytes), signedPeakDelta=\(signedPeakDelta)
        signedRetainedDelta=\(signedRetainedDelta), samples=\(peak.sampleCount)
        samplingIntervalSeconds=0.001, opaqueNativeAllocation=unmeasured
        """)
    #expect(uploadDuration <= halfFrameBudget)
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
    let plan = try MeshSourcePresentationRenderPlan(scene: scene)

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

private func presentationHighSegmentCylinderSource(
    segmentCount: Int,
    cylinderCount: Int = 1
) throws -> MeshSource {
    let radius = 0.035
    let length = 0.45
    var builder = MeshSourceBuilder(identity: "mesh.presentation-high-segment-cylinder")
    try builder.reserveCapacity(
        vertexCount: cylinderCount * 2 * segmentCount,
        faceCount: cylinderCount * (segmentCount + 2),
        cornerCount: cylinderCount * 6 * segmentCount
    )
    for cylinderIndex in 0..<cylinderCount {
        let centerX = 10.0 + Double(cylinderIndex % 4) * 0.20
        let centerY = -7.0 + Double(cylinderIndex / 4) * 0.20
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
                    GeometryPoint3D(x: x, y: y, z: 0)
                )
            )
            topVertices.append(
                try builder.addVertex(
                    GeometryPoint3D(x: x, y: y, z: length)
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
