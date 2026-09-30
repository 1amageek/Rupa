import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

/// A command that reads evaluated topology reads the store's current evaluation, a command that
/// must read the document it just changed evaluates only what changed, and a direct edit leaves
/// "does it evaluate" to the store's own evaluation boundary.
@Suite struct CommandEvaluationReuseTests {
    private func boxes(_ count: Int) throws -> DesignDocument {
        var document = DesignDocument.empty(named: "Reuse")
        for index in 0..<count {
            _ = try document.createExtrudedRectangle(
                name: "Box \(index)", plane: .xy,
                width: .length(0.1, .meter), height: .length(0.1, .meter), depth: .length(0.1, .meter),
                direction: .normal
            )
        }
        return document
    }

    private func evaluatedStore(_ document: DesignDocument) -> CADDocumentStore {
        let store = CADDocumentStore(document: document)
        store.evaluateCurrentDocument()
        return store
    }

    private func topFace(of document: DesignDocument) throws -> SelectionTarget {
        let faces = try TopologySnapshotService().snapshot(document: document).entries.filter { $0.kind == .face }
        let top = try #require(faces.max { ($0.center?.z ?? 0) < ($1.center?.z ?? 0) })
        return try #require(top.selectionTarget())
    }

    @Test(.timeLimit(.minutes(1)))
    func aTopologyCommandThroughTheStoreEvaluatesNothingFromScratch() throws {
        let store = evaluatedStore(try boxes(3))
        #expect(store.evaluationStatus == .valid)
        let face = try topFace(of: store.document)
        let probe = DocumentWorkProbe()
        try DocumentWorkProbe.$current.withValue(probe) {
            _ = try store.apply(.deleteBodyFaces(targets: [face]))
        }
        #expect(store.evaluationStatus == .valid)
        #expect(probe.evaluationFromScratchCount == 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func aDirectEditLeavesItsEvaluationToTheStore() throws {
        let store = evaluatedStore(try boxes(3))
        let face = try topFace(of: store.document)
        let passes = store.completedEvaluationPassCount
        let probe = DocumentWorkProbe()
        try DocumentWorkProbe.$current.withValue(probe) {
            _ = try store.apply(.moveBodyFaces(targets: [face], direction: .unitZ, distance: .length(0.01, .meter)))
        }
        #expect(store.evaluationStatus == .valid)
        #expect(probe.evaluationFromScratchCount == 0)
        #expect(probe.incrementalEvaluationCount == 0)
        #expect(store.completedEvaluationPassCount == passes + 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func aChangedDocumentIsEvaluatedFromTheCurrentEvaluation() throws {
        let store = evaluatedStore(try boxes(3))
        let current = try #require(store.currentEvaluation)
        var changed = store.document
        _ = try changed.createExtrudedRectangle(
            name: "Added", plane: .xy,
            width: .length(0.05, .meter), height: .length(0.05, .meter), depth: .length(0.05, .meter),
            direction: .normal
        )
        let probe = DocumentWorkProbe()
        let reused = try DocumentWorkProbe.$current.withValue(probe) {
            try DocumentEvaluationContextResolver().exactEvaluatedDocument(
                document: changed, currentEvaluation: current, currentGeneration: store.generation,
                failurePrefix: "Reuse"
            )
        }
        #expect(probe.incrementalEvaluationCount == 1)
        #expect(probe.evaluationFromScratchCount == 0)
        let metrics = reused.evaluationMetrics
        #expect(metrics.totalFeatureCount == changed.cadDocument.designGraph.order.count)
        #expect(metrics.reusedFeatureCount == store.document.cadDocument.designGraph.order.count)
        #expect(metrics.rebuiltFeatureCount == metrics.totalFeatureCount - metrics.reusedFeatureCount)

        let fresh = try DocumentEvaluationContextResolver().exactEvaluatedDocument(
            document: changed, failurePrefix: "Reuse"
        )
        #expect(Set(reused.subshapes.entries.keys) == Set(fresh.subshapes.entries.keys))
        #expect(reused.brep.bodies.count == fresh.brep.bodies.count)
        #expect(reused.brep.faces.count == fresh.brep.faces.count)
    }
}
