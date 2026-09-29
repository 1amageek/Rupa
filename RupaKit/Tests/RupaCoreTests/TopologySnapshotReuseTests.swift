import Foundation
import SwiftCAD
import Synchronization
import Testing
@testable import RupaCore

/// Work already done for a document generation is reused: a snapshot of the current evaluation
/// evaluates nothing, and many targets resolve against one snapshot.
@MainActor
@Suite struct TopologySnapshotReuseTests {
    /// Counts exact evaluations while delegating to the real evaluator.
    private final class CountingEvaluator: ExactDocumentEvaluating, Sendable {
        private let base: any ExactDocumentEvaluating
        private let calls = Mutex(0)
        var evaluationTolerance: ModelingTolerance { base.evaluationTolerance }
        var count: Int { calls.withLock { $0 } }

        init(base: any ExactDocumentEvaluating) {
            self.base = base
        }

        func evaluateExact(_ document: CADDocument) throws -> EvaluatedDocument {
            calls.withLock { $0 += 1 }
            return try base.evaluateExact(document)
        }
    }

    private static let corners: [BodyCornerEdge] = [.leftBottom, .rightBottom, .rightTop, .leftTop]

    private func box() throws -> (EditorSession, SceneNodeID, CountingEvaluator) {
        let session = EditorSession()
        _ = try #require(session.createDefaultExtrudedRectangle())
        let featureID = try #require(session.document.cadDocument.designGraph.order.last)
        let node = try #require(session.document.productMetadata.sceneNodes.values.first {
            $0.reference?.featureID == featureID
        }).id
        let counter = CountingEvaluator(base: try DocumentEvaluator.modelingDefault(for: session.document))
        return (session, node, counter)
    }

    @Test func aSnapshotOfTheCurrentEvaluationEvaluatesNothing() throws {
        let (session, _, counter) = try box()
        let service = TopologySnapshotService(exactEvaluator: counter)
        let current = try service.snapshot(document: session.document,
            currentEvaluation: session.currentEvaluation, currentGeneration: session.generation)
        #expect(counter.count == 0)
        let fresh = try service.snapshot(document: session.document)
        #expect(counter.count == 1)
        #expect(current == fresh)
    }

    /// Four corner edges resolved one by one evaluate the document four times; against one shared
    /// snapshot, once, with the same answers.
    @Test func manyTargetsResolveAgainstOneSnapshot() throws {
        let (session, node, counter) = try box()
        let service = TopologySnapshotService(exactEvaluator: counter)
        let resolver = GeneratedTopologySelectionResolver(topologyService: service)
        let targets = try Self.corners.map { corner in
            SelectionTarget(sceneNodeID: node, component: .edge(try #require(
                try GeneratedTopologySelectionResolver().componentID(for: node, cornerEdge: corner, in: session.document)
            )))
        }
        let oneByOne = try targets.map { try resolver.cornerEdge(for: $0, in: session.document) }
        #expect(counter.count == targets.count)
        let before = counter.count
        let snapshot = try service.snapshot(document: session.document)
        let shared = try targets.map { try resolver.cornerEdge(for: $0, in: session.document, topology: snapshot) }
        #expect(counter.count == before + 1)
        #expect(shared == oneByOne)
        #expect(Set(shared) == Set(Self.corners))
    }

    /// A read-only service handed a matching evaluation does not validate the document again:
    /// a document altered after its evaluation (which no generation would allow) still passes, so
    /// no validation ran, while without the evaluation the alteration is caught.
    @Test func aMatchingEvaluationSparesTheValidation() throws {
        let (session, _, _) = try box()
        var altered = session.document
        altered.productMetadata.rootSceneNodeIDs.append(SceneNodeID())
        #expect(throws: (any Error).self) { try altered.validate() }
        try altered.validate(objectRegistry: .builtIn,
            unlessEvaluatedBy: session.currentEvaluation, generation: session.generation)
        #expect(throws: (any Error).self) {
            try altered.validate(objectRegistry: .builtIn, unlessEvaluatedBy: nil, generation: session.generation)
        }
    }
}
