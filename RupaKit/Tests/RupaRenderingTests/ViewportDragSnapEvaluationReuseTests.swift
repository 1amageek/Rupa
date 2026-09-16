import RupaCore
import RupaViewportScene
import SwiftCAD
import Testing
@testable import RupaRendering

/// Refuses every exact kernel evaluation, so a route that asks for one fails
/// and a route that reuses the caller's evaluation answers. The difference
/// between those two outcomes is what these tests read.
private struct RefusingExactDocumentEvaluator: ExactDocumentEvaluating {
    enum Refusal: Error {
        case exactEvaluationWasRequested
    }

    let evaluationTolerance: ModelingTolerance = .standard

    func evaluateExact(_ document: CADDocument) throws -> EvaluatedDocument {
        throw Refusal.exactEvaluationWasRequested
    }
}

private func dragSnapEvaluationReuseOptions() -> SnapResolutionOptions {
    SnapResolutionOptions(
        usesGrid: true,
        usesObjects: true,
        gridIntervalMeters: 0.001,
        objectSearchRadiusMeters: 0.001,
        maximumCandidateCount: 4
    )
}

private func refusingSnapResolver() -> SnapResolver {
    SnapResolver(
        topologySnapshotService: TopologySnapshotService(
            exactEvaluator: RefusingExactDocumentEvaluator()
        )
    )
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func canvasDragSnapResolverResolvesBothEndsFromTheCallersEvaluationContext() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let document = session.document
    let generation = session.generation
    let currentEvaluation = try #require(session.currentEvaluation)

    let drag = ViewportModelDrag(
        start: Point2D(x: 0.0014, y: 0.0026),
        end: Point2D(x: 0.0032, y: 0.0041),
        sketchPlane: .xy
    )
    let ruler = RulerConfiguration.standard(for: .millimeter)
    let options = dragSnapEvaluationReuseOptions()
    let resolver = ViewportCanvasDragSnapResolver(
        resolver: ViewportSnapResolutionService(snapResolver: refusingSnapResolver())
    )

    let withoutContext = resolver.resolution(
        drag,
        document: document,
        ruler: ruler,
        snapOptions: options,
        axisConstraint: nil
    )
    #expect(withoutContext.failureDescriptions.count == 2)

    let withoutGeneration = resolver.resolution(
        drag,
        document: document,
        ruler: ruler,
        snapOptions: options,
        axisConstraint: nil,
        currentEvaluation: currentEvaluation,
        currentGeneration: nil
    )
    #expect(withoutGeneration.failureDescriptions.count == 2)

    let reused = resolver.resolution(
        drag,
        document: document,
        ruler: ruler,
        snapOptions: options,
        axisConstraint: nil,
        currentEvaluation: currentEvaluation,
        currentGeneration: generation
    )
    #expect(reused.failureDescriptions.isEmpty)

    let evaluated = ViewportCanvasDragSnapResolver().resolution(
        drag,
        document: document,
        ruler: ruler,
        snapOptions: options,
        axisConstraint: nil
    )
    #expect(evaluated.failureDescriptions.isEmpty)
    #expect(reused.drag == evaluated.drag)
    #expect(withoutContext.drag != evaluated.drag)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func constructionPlaneDragSnapResolverResolvesFromTheCallersEvaluationContext() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let document = session.document
    let generation = session.generation
    let currentEvaluation = try #require(session.currentEvaluation)

    let target = ViewportConstructionPlaneDragTarget(
        constructionPlaneID: ConstructionPlaneSourceID(),
        sceneNodeID: SceneNodeID(),
        handle: .origin,
        origin: Point3D(x: 0.0014, y: 0.0, z: 0.0026),
        normal: .unitY
    )
    let ruler = RulerConfiguration.standard(for: .millimeter)
    let options = dragSnapEvaluationReuseOptions()
    let resolver = ViewportConstructionPlaneDragSnapResolver(
        snapResolver: refusingSnapResolver()
    )

    let withoutContext = resolver.snappedTarget(
        target,
        document: document,
        ruler: ruler,
        options: options
    )
    #expect(withoutContext == target)

    let withoutGeneration = resolver.snappedTarget(
        target,
        document: document,
        ruler: ruler,
        options: options,
        currentEvaluation: currentEvaluation,
        currentGeneration: nil
    )
    #expect(withoutGeneration == target)

    let reused = resolver.snappedTarget(
        target,
        document: document,
        ruler: ruler,
        options: options,
        currentEvaluation: currentEvaluation,
        currentGeneration: generation
    )
    let evaluated = ViewportConstructionPlaneDragSnapResolver().snappedTarget(
        target,
        document: document,
        ruler: ruler,
        options: options
    )
    #expect(evaluated != target)
    #expect(reused == evaluated)
}
