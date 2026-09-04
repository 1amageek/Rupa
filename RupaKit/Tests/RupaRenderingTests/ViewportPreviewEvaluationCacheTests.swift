import Foundation
import RupaCore
import RupaViewportScene
import SwiftCAD
import Testing
@testable import RupaRendering

@MainActor
@Test(.timeLimit(.minutes(1)))
func viewportPreviewEvaluationDoesNotEvaluateWhilePreparing() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let preview = try previewChamferDocument(from: session.document)
    let cache = ViewportPreviewEvaluationCache()

    cache.prepare(
        document: preview,
        generation: DocumentGeneration(1),
        revision: 1,
        reusing: nil,
        objectRegistry: .builtIn
    )

    guard case .preparing(let revision) = cache.state else {
        Issue.record("Preview evaluation must not complete on the calling actor.")
        return
    }
    #expect(revision == 1)
    #expect(cache.isReady(for: 1) == false)
    #expect(cache.readyCache(for: 1) == nil)

    try await settle(cache, revision: 1)
    #expect(cache.isReady(for: 1))
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func viewportPreviewEvaluationSuppliesAMatchingEvaluationToSceneConstruction() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let preview = try previewChamferDocument(from: session.document)
    let generation = DocumentGeneration(4)
    let cache = ViewportPreviewEvaluationCache()

    cache.prepare(
        document: preview,
        generation: generation,
        revision: 1,
        reusing: nil,
        objectRegistry: .builtIn
    )
    try await settle(cache, revision: 1)

    let evaluationCache = try #require(cache.readyCache(for: 1))
    let projected = ViewportSceneBuilder().build(
        document: preview,
        ruler: .standard(for: .meter),
        documentGeneration: generation,
        evaluationCache: evaluationCache,
        evaluationPolicy: .suppliedOnly
    )
    let unevaluated = ViewportSceneBuilder().build(
        document: preview,
        ruler: .standard(for: .meter),
        evaluationPolicy: .suppliedOnly
    )

    // The preview document has no published generation, so only the evaluation
    // this cache prepared can match it. Without that supplied evaluation the same
    // build carries no evaluated body identity at all.
    #expect(evaluatedBodyIDCount(in: projected) > 0)
    #expect(evaluatedBodyIDCount(in: unevaluated) == 0)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func viewportPreviewEvaluationDiscardsAStaleRevision() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let firstPreview = try previewChamferDocument(from: session.document, distance: 0.001)
    let secondPreview = try previewChamferDocument(from: session.document, distance: 0.002)
    let cache = ViewportPreviewEvaluationCache()

    cache.prepare(
        document: firstPreview,
        generation: DocumentGeneration(1),
        revision: 1,
        reusing: nil,
        objectRegistry: .builtIn
    )
    cache.prepare(
        document: secondPreview,
        generation: DocumentGeneration(1),
        revision: 2,
        reusing: nil,
        objectRegistry: .builtIn
    )
    try await settle(cache, revision: 2)

    #expect(cache.isReady(for: 2))
    #expect(cache.isReady(for: 1) == false)
    #expect(cache.readyCache(for: 1) == nil)
    #expect(cache.failureMessage(for: 1) == nil)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func viewportPreviewEvaluationCoalescesRequestsMadeDuringOneDrag() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let previews = try (1...4).map { step in
        try previewChamferDocument(from: session.document, distance: 0.0005 * Double(step))
    }
    let cache = ViewportPreviewEvaluationCache()

    for (index, preview) in previews.enumerated() {
        cache.prepare(
            document: preview,
            generation: DocumentGeneration(1),
            revision: UInt64(index + 1),
            reusing: nil,
            objectRegistry: .builtIn
        )
    }
    try await settle(cache, revision: 4)

    // One evaluation was already running when the drag continued, so exactly one
    // more starts: the newest waiting revision. Intermediate revisions never run.
    #expect(cache.startedEvaluationCount == 2)
    #expect(cache.isReady(for: 4))
    #expect(cache.isReady(for: 2) == false)
    #expect(cache.isReady(for: 3) == false)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func viewportPreviewEvaluationClearReturnsToIdleAndRejectsLateCompletion() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let preview = try previewChamferDocument(from: session.document)
    let cache = ViewportPreviewEvaluationCache()

    cache.prepare(
        document: preview,
        generation: DocumentGeneration(1),
        revision: 1,
        reusing: nil,
        objectRegistry: .builtIn
    )
    cache.clear()

    guard case .idle = cache.state else {
        Issue.record("Clearing the preview must return the cache to idle.")
        return
    }

    // The evaluator does not observe cancellation, so the abandoned evaluation
    // still completes. Wait for that completion instead of a fixed delay, so the
    // assertion below rejects a late result rather than outrunning it.
    try await settleCompletion(cache, count: 1)

    guard case .idle = cache.state else {
        Issue.record("A late completion must never replace cleared preview state.")
        return
    }
    #expect(cache.isReady(for: 1) == false)
    #expect(cache.readyCache(for: 1) == nil)
    #expect(cache.failureMessage(for: 1) == nil)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func viewportPreviewEvaluationReportsFailureInsteadOfAnEmptySuccess() async throws {
    let missingFeatureID = FeatureID()
    let invalidPreview = DesignDocument(
        cadDocument: CADDocument(
            units: .meters,
            designGraph: DesignGraph(
                nodes: [:],
                order: [missingFeatureID]
            )
        )
    )
    let cache = ViewportPreviewEvaluationCache()

    cache.prepare(
        document: invalidPreview,
        generation: DocumentGeneration(1),
        revision: 1,
        reusing: nil,
        objectRegistry: .builtIn
    )
    try await settle(cache, revision: 1)

    let message = try #require(cache.failureMessage(for: 1))
    #expect(!message.isEmpty)
    #expect(cache.isReady(for: 1) == false)
    #expect(cache.readyCache(for: 1) == nil)
}

@MainActor
private func settle(
    _ cache: ViewportPreviewEvaluationCache,
    revision: UInt64
) async throws {
    for _ in 0..<600 {
        if cache.isReady(for: revision) || cache.failureMessage(for: revision) != nil {
            return
        }
        try await Task.sleep(for: .milliseconds(20))
    }
    Issue.record("Preview evaluation did not settle for revision \(revision).")
}

@MainActor
private func settleCompletion(
    _ cache: ViewportPreviewEvaluationCache,
    count: Int
) async throws {
    for _ in 0..<600 {
        if cache.completedEvaluationCount >= count {
            return
        }
        try await Task.sleep(for: .milliseconds(20))
    }
    Issue.record("Preview evaluation did not complete \(count) time(s).")
}

@MainActor
private func previewChamferDocument(
    from document: DesignDocument,
    distance: Double = 0.001
) throws -> DesignDocument {
    let bodyFeatureID = try #require(document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(
        document.productMetadata.sceneNodes.first { entry in
            entry.value.reference?.kind == .body && entry.value.reference?.featureID == bodyFeatureID
        }?.key
    )
    return try ViewportEdgeTreatmentPreviewDocumentBuilder().previewDocument(
        for: .chamfer(
            target: SelectionTarget(sceneNodeID: bodyNodeID, component: .edge(.bodyEdgeRightTop)),
            distance: distance
        ),
        in: document
    )
}

/// How many body items carry the identity that only an evaluated document
/// supplies. Item presence alone is produced from the non-evaluated design
/// snapshot and therefore proves nothing about evaluation.
private func evaluatedBodyIDCount(in scene: ViewportScene) -> Int {
    scene.items.reduce(into: 0) { count, item in
        guard case .body(let component) = item.kind, component.bodyID != nil else {
            return
        }
        count += 1
    }
}
