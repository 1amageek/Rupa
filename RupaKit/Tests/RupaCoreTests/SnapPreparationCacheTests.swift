import SwiftCAD
import Testing
@testable import RupaCore

/// Snapping prepares a published document state once: pointer moves over the same state reuse
/// the preparation and answer exactly what a fresh preparation answers.
@MainActor
@Suite struct SnapPreparationCacheTests {
    private let options = SnapResolutionOptions(
        usesGrid: false,
        usesObjects: true,
        gridIntervalMeters: 0.001,
        objectSearchRadiusMeters: 0.05,
        maximumCandidateCount: 32
    )

    @Test func pointerMovesOverOneStateReuseItsPreparation() throws {
        let session = EditorSession()
        _ = try #require(session.createDefaultExtrudedRectangle())
        let cache = SnapPreparationCache()
        let resolver = SnapResolver(preparationCache: cache)
        let points = [Point2D(x: 0.001, y: 0.002), Point2D(x: -0.01, y: 0.015), Point2D(x: 0.02, y: -0.004)]
        for point in points {
            let cached = try resolver.resolve(point: point, in: session.document, ruler: .standard(for: .millimeter),
                options: options, currentEvaluation: session.currentEvaluation, currentGeneration: session.generation)
            let fresh = try SnapResolver(preparationCache: SnapPreparationCache()).resolve(
                point: point, in: session.document, ruler: .standard(for: .millimeter), options: options)
            #expect(cached == fresh)
            #expect(!cached.candidates.isEmpty)
        }
        #expect(cache.preparationCount == 1)

        // A new document state is prepared anew.
        _ = try #require(session.createDefaultExtrudedRectangle())
        _ = try resolver.resolve(point: points[0], in: session.document, ruler: .standard(for: .millimeter),
            options: options, currentEvaluation: session.currentEvaluation, currentGeneration: session.generation)
        #expect(cache.preparationCount == 2)
    }

    /// Without the document's current evaluation nothing names its state, so nothing is kept.
    @Test func aDocumentWithoutItsEvaluationIsNotKept() throws {
        let session = EditorSession()
        _ = try #require(session.createDefaultExtrudedRectangle())
        let cache = SnapPreparationCache()
        let resolver = SnapResolver(preparationCache: cache)
        for _ in 0..<2 {
            _ = try resolver.resolve(point: Point2D(x: 0.001, y: 0.002), in: session.document,
                ruler: .standard(for: .millimeter), options: options)
        }
        #expect(cache.preparationCount == 0)
    }
}
