import Testing
import SwiftCAD
@testable import RupaCore

@MainActor
@Test func cadDocumentStoreRejectsMismatchedInitialEvaluationCache() async throws {
    let rectangleSession = EditorSession()
    _ = try #require(rectangleSession.createDefaultExtrudedRectangle())
    let rectangleCache = try #require(rectangleSession.currentEvaluationCache)

    let circleSession = EditorSession()
    _ = try #require(circleSession.createDefaultExtrudedCircle())

    let store = CADDocumentStore(
        document: circleSession.document,
        generation: rectangleCache.generation,
        evaluationStatus: .valid,
        evaluatedGeneration: rectangleCache.generation,
        evaluatedBodyCount: rectangleCache.evaluatedDocument.meshes.count,
        evaluationCache: rectangleCache
    )

    #expect(store.currentEvaluationCache == nil)
    #expect(store.currentEvaluation == nil)
}

@MainActor
@Test func cadDocumentStoreDropsPreservedCacheWhenRestoredDocumentSourceDiffers() async throws {
    let rectangleSession = EditorSession()
    _ = try #require(rectangleSession.createDefaultExtrudedRectangle())
    let rectangleCache = try #require(rectangleSession.currentEvaluationCache)

    let circleSession = EditorSession()
    _ = try #require(circleSession.createDefaultExtrudedCircle())

    let store = CADDocumentStore(
        document: rectangleSession.document,
        generation: rectangleSession.generation,
        evaluationStatus: .valid,
        evaluatedGeneration: rectangleSession.generation,
        evaluatedBodyCount: rectangleSession.evaluatedBodyCount,
        evaluationCache: rectangleCache
    )
    #expect(store.currentEvaluationCache != nil)

    store.restore(
        DocumentSnapshot(
            document: circleSession.document,
            generation: rectangleSession.generation,
            isDirty: false,
            diagnostics: [],
            evaluationStatus: .valid,
            evaluatedGeneration: rectangleSession.generation,
            renderInvalidation: RenderInvalidation(
                generation: rectangleSession.generation,
                reason: .evaluated
            ),
            evaluatedBodyCount: rectangleSession.evaluatedBodyCount
        )
    )

    #expect(store.currentEvaluationCache == nil)
    #expect(store.currentEvaluation == nil)
}

@MainActor
@Test func summaryServicesUseCurrentEvaluationContextBeforeEvaluatingPipeline() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let currentEvaluation = try #require(session.currentEvaluation)
    let failingPipeline = CADPipeline(
        evaluator: DocumentEvaluator(featureEvaluator: ContextFailingFeatureEvaluator())
    )

    let meshSummary = try MeshSummaryService(pipeline: failingPipeline).summarize(
        document: session.document,
        ruler: session.workspaceState.ruler,
        currentEvaluation: currentEvaluation,
        currentGeneration: session.generation
    )
    let topologySummary = try TopologySummaryService(pipeline: failingPipeline).summarize(
        document: session.document,
        displayUnit: session.workspaceState.displayUnit,
        currentEvaluation: currentEvaluation,
        currentGeneration: session.generation
    )
    let surfaceAnalysis = try SurfaceAnalysisService(
        pipeline: failingPipeline,
        options: SurfaceAnalysisOptions(sampleDensity: .low)
    ).analyze(
        document: session.document,
        displayUnit: .millimeter,
        currentEvaluation: currentEvaluation,
        currentGeneration: session.generation
    )
    let surfaceContinuity = try SurfaceContinuityService(pipeline: failingPipeline).summarize(
        document: session.document,
        displayUnit: session.workspaceState.displayUnit,
        currentEvaluation: currentEvaluation,
        currentGeneration: session.generation
    )
    let displaySnapshot = try DesignDisplaySnapshotService(
        pipeline: failingPipeline
    ).result(
        document: session.document,
        workspaceState: session.workspaceState,
        currentEvaluation: currentEvaluation,
        generation: session.generation,
        dirty: session.isDirty
    )

    #expect(meshSummary.bodyCount == 1)
    #expect(topologySummary.counts.bodyCount == 1)
    #expect(surfaceAnalysis.counts.bSplineFaceCount == 0)
    #expect(surfaceContinuity.counts.bSplineFaceCount == 0)
    #expect(displaySnapshot.bodies.count == 1)
}

@MainActor
@Test func summaryServicesIgnoreCurrentEvaluationContextWhenGenerationDiffers() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let currentEvaluation = try #require(session.currentEvaluation)
    let failingPipeline = CADPipeline(
        evaluator: DocumentEvaluator(featureEvaluator: ContextFailingFeatureEvaluator())
    )

    do {
        _ = try MeshSummaryService(pipeline: failingPipeline).summarize(
            document: session.document,
            ruler: session.workspaceState.ruler,
            currentEvaluation: currentEvaluation,
            currentGeneration: DocumentGeneration(session.generation.value + 1)
        )
        Issue.record("Mismatched generation must not use the current evaluation context.")
    } catch let error as EditorError {
        #expect(error.code == .evaluationFailed)
        #expect(error.message.contains("Injected evaluator should not be used."))
    }
}

@MainActor
@Test func summaryServicesIgnoreCurrentEvaluationContextWhenSourceFingerprintDiffers() async throws {
    let rectangleSession = EditorSession()
    _ = try #require(rectangleSession.createDefaultExtrudedRectangle())
    let currentEvaluation = try #require(rectangleSession.currentEvaluation)

    let circleSession = EditorSession()
    _ = try #require(circleSession.createDefaultExtrudedCircle())
    let failingPipeline = CADPipeline(
        evaluator: DocumentEvaluator(featureEvaluator: ContextFailingFeatureEvaluator())
    )

    do {
        _ = try MeshSummaryService(pipeline: failingPipeline).summarize(
            document: circleSession.document,
            ruler: circleSession.workspaceState.ruler,
            currentEvaluation: currentEvaluation,
            currentGeneration: rectangleSession.generation
        )
        Issue.record("Mismatched source fingerprint must not use the current evaluation context.")
    } catch let error as EditorError {
        #expect(error.code == .evaluationFailed)
        #expect(error.message.contains("Injected evaluator should not be used."))
    }
}

@MainActor
@Test func measurementServiceUsesCurrentEvaluationContextBeforeEvaluatingPipeline() async throws {
    var document = DesignDocument.empty()
    let profileID = try document.createRectangleSketchFromCorners(
        name: "Revolve Profile",
        plane: .xy,
        firstCorner: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        oppositeCorner: SketchPoint(
            x: .length(4.0, .millimeter),
            y: .length(12.0, .millimeter)
        )
    )
    _ = try document.createRevolve(
        name: "Revolved Body",
        profile: ProfileReference(featureID: profileID),
        axis: RevolveAxis(origin: .origin, direction: .unitY),
        angle: .angle(180.0, .degree)
    )
    let session = EditorSession(document: document)
    session.store.evaluateCurrentDocument()
    let currentEvaluation = try #require(session.currentEvaluation)
    let failingPipeline = CADPipeline(
        evaluator: DocumentEvaluator(featureEvaluator: ContextFailingFeatureEvaluator())
    )

    let result = try MeasurementService(pipeline: failingPipeline).measure(
        document: session.document,
        ruler: session.workspaceState.ruler,
        currentEvaluation: currentEvaluation,
        currentGeneration: session.generation
    )

    #expect(result.counts.solids == 1)
    #expect(result.diagnostics.contains { $0.message.contains("Injected evaluator should not be used.") } == false)
}

@MainActor
@Test func surfaceFrameServiceUsesCurrentEvaluationContextBeforeEvaluatingPipeline() async throws {
    var document = DesignDocument.empty()
    _ = try document.createPolySplineSurface(
        name: "Context Frame Surface",
        sourceMesh: contextFramePolySplinePatchNetworkMesh(centerZ: 0.0),
        options: PolySplineOptions(mergePatches: false)
    )
    let session = EditorSession(document: document)
    session.store.evaluateCurrentDocument()
    let currentEvaluation = try #require(session.currentEvaluation)
    let topology = try TopologySnapshotService().snapshot(
        document: session.document,
        currentEvaluation: currentEvaluation,
        currentGeneration: session.generation
    )
    let faceEntry = try #require(topology.entries.first { $0.kind == .face })
    let failingPipeline = CADPipeline(
        evaluator: DocumentEvaluator(featureEvaluator: ContextFailingFeatureEvaluator())
    )

    let result = try SurfaceFrameService(pipeline: failingPipeline).resolve(
        document: session.document,
        queries: [
            SurfaceFrameQuery(
                facePersistentName: faceEntry.persistentName,
                u: 0.5,
                v: 0.5
            ),
        ],
        displayUnit: session.workspaceState.displayUnit,
        currentEvaluation: currentEvaluation,
        currentGeneration: session.generation
    )

    #expect(result.frames.count == 1)
}

@MainActor
@Test func selectionDimensionServiceUsesCurrentEvaluationContextBeforeEvaluatingPipeline() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let currentEvaluation = try #require(session.currentEvaluation)
    let failingPipeline = CADPipeline(
        evaluator: DocumentEvaluator(featureEvaluator: ContextFailingFeatureEvaluator())
    )

    let result = try SelectionDimensionService(pipeline: failingPipeline).evaluate(
        document: session.document,
        displayUnit: session.workspaceState.displayUnit,
        currentEvaluation: currentEvaluation,
        currentGeneration: session.generation
    )

    #expect(result.measurements.isEmpty)
}

private struct ContextFailingFeatureEvaluator: FeatureEvaluating {
    func evaluate(feature _: FeatureNode, context _: EvaluationContext) throws -> EvaluationResult {
        throw FeatureEvaluationError.unsupportedOperation("Injected evaluator should not be used.")
    }
}

private func contextFramePolySplinePatchNetworkMesh(centerZ: Double) -> Mesh {
    Mesh(
        positions: [
            Point3D(x: 0.0, y: 0.0, z: 0.0),
            Point3D(x: 0.01, y: 0.0, z: 0.0),
            Point3D(x: 0.02, y: 0.0, z: 0.0),
            Point3D(x: 0.0, y: 0.01, z: 0.0),
            Point3D(x: 0.01, y: 0.01, z: centerZ),
            Point3D(x: 0.02, y: 0.01, z: 0.0),
        ],
        indices: [
            0, 1, 4,
            0, 4, 3,
            1, 2, 5,
            1, 5, 4,
        ]
    )
}
