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
        currentEvaluation: currentEvaluation,
        currentGeneration: session.generation
    )
    let topologySummary = try TopologySummaryService(pipeline: failingPipeline).summarize(
        document: session.document,
        currentEvaluation: currentEvaluation,
        currentGeneration: session.generation
    )
    let surfaceAnalysis = try SurfaceAnalysisService(
        pipeline: failingPipeline,
        options: SurfaceAnalysisOptions(sampleDensity: .low)
    ).analyze(
        document: session.document,
        currentEvaluation: currentEvaluation,
        currentGeneration: session.generation
    )
    let surfaceContinuity = try SurfaceContinuityService(pipeline: failingPipeline).summarize(
        document: session.document,
        currentEvaluation: currentEvaluation,
        currentGeneration: session.generation
    )
    let displaySnapshot = try DesignDisplaySnapshotService(
        bodyService: BodyDisplaySnapshotService(pipeline: failingPipeline)
    ).result(
        document: session.document,
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
            currentEvaluation: currentEvaluation,
            currentGeneration: DocumentGeneration(session.generation.value + 1)
        )
        Issue.record("Mismatched generation must not use the current evaluation context.")
    } catch let error as EditorError {
        #expect(error.code == .evaluationFailed)
        #expect(error.message.contains("Injected evaluator should not be used."))
    }
}

private struct ContextFailingFeatureEvaluator: FeatureEvaluating {
    func evaluate(feature _: FeatureNode, context _: EvaluationContext) throws -> EvaluationResult {
        throw FeatureEvaluationError.unsupportedOperation("Injected evaluator should not be used.")
    }
}
