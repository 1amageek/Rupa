import Foundation
import RupaCore
import RupaViewportScene
import SwiftCAD
import Testing

@MainActor
@Test(.timeLimit(.minutes(1)))
func viewportSceneBuilderEvaluatesOnDemandWhenNoEvaluationIsSupplied() throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)

    let scene = ViewportSceneBuilder().build(
        document: session.document,
        ruler: .standard(for: .meter),
        evaluationPolicy: .evaluateOnDemand
    )

    #expect(evaluatedBodyID(in: scene, featureID: bodyFeatureID) != nil)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func viewportSceneBuilderNeverEvaluatesUnderSuppliedOnlyPolicy() throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)

    let scene = ViewportSceneBuilder().build(
        document: session.document,
        ruler: .standard(for: .meter),
        evaluationPolicy: .suppliedOnly
    )

    #expect(evaluatedBodyID(in: scene, featureID: bodyFeatureID) == nil)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func viewportSceneBuilderProjectsSuppliedEvaluationUnderSuppliedOnlyPolicy() throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let generation = DocumentGeneration(7)
    let evaluationCache = try #require(
        EvaluationScheduler().evaluateResult(
            document: session.document,
            generation: generation
        ).evaluationCache
    )

    let scene = ViewportSceneBuilder().build(
        document: session.document,
        ruler: .standard(for: .meter),
        documentGeneration: generation,
        evaluationCache: evaluationCache,
        evaluationPolicy: .suppliedOnly
    )

    #expect(evaluatedBodyID(in: scene, featureID: bodyFeatureID) != nil)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func viewportSceneBuilderRejectsStaleSuppliedEvaluationUnderSuppliedOnlyPolicy() throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let evaluationCache = try #require(
        EvaluationScheduler().evaluateResult(
            document: session.document,
            generation: DocumentGeneration(7)
        ).evaluationCache
    )

    let scene = ViewportSceneBuilder().build(
        document: session.document,
        ruler: .standard(for: .meter),
        documentGeneration: DocumentGeneration(8),
        evaluationCache: evaluationCache,
        evaluationPolicy: .suppliedOnly
    )

    #expect(evaluatedBodyID(in: scene, featureID: bodyFeatureID) == nil)
}

/// The identity a body item carries only when the build projected an evaluated
/// document. An extrude item itself is produced from the non-evaluated design
/// snapshot, so its presence proves nothing about evaluation; this identity does.
private func evaluatedBodyID(
    in scene: ViewportScene,
    featureID: FeatureID
) -> String? {
    for item in scene.items where item.featureID == featureID {
        guard case .body(let component) = item.kind else {
            continue
        }
        return component.bodyID
    }
    return nil
}
