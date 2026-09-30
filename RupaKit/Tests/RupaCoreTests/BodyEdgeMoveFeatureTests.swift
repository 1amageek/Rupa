import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

/// Move Edges appends the kernel's edge move: straight edges of planar solids and circular edges
/// along their axis, keeping the selection on the moved edges.
@Suite struct BodyEdgeMoveFeatureTests {
    private func edges(of document: DesignDocument) throws -> [TopologySummaryResult.Entry] {
        try TopologySnapshotService().snapshot(document: document).entries.filter { $0.kind == .edge }
    }

    @Test func aStraightEdgeMovesAndTheSelectionFollowsIt() throws {
        var document = DesignDocument.empty()
        _ = try document.createExtrudedRectangle(
            name: "Box", plane: .xy, width: .length(0.1, .meter), height: .length(0.1, .meter),
            depth: .length(0.1, .meter), direction: .normal
        )
        let all = try edges(of: document)
        let maxX = all.compactMap { $0.midpoint?.x }.max() ?? 0
        let maxZ = all.compactMap { $0.midpoint?.z }.max() ?? 0
        // The top edge on the +X side, running along Y.
        let entry = try #require(all.first { entry in
            guard entry.curveKind == "line", let mid = entry.midpoint else { return false }
            return abs(mid.x - maxX) < 1e-9 && abs(mid.z - maxZ) < 1e-9
        })
        let target = try #require(entry.selectionTarget())

        try document.moveBodyEdges(targets: [target], direction: .unitX, distance: .length(0.02, .meter))
        let moveID = try #require(document.cadDocument.designGraph.order.last)
        guard case .edgeMove = document.cadDocument.designGraph.nodes[moveID]?.operation else {
            Issue.record("Expected an edge move feature.")
            return
        }
        #expect(document.productMetadata.sceneNodes[target.sceneNodeID]?.reference?.featureID == moveID)
        let moved = try #require(try document.topologyTargets(following: [target], to: moveID).first)
        let movedEntry = try #require(try edges(of: document).first { $0.selectionTarget() == moved })
        #expect(abs((movedEntry.midpoint?.x ?? 0) - (maxX + 0.02)) < 1e-9)
        #expect(abs((movedEntry.midpoint?.z ?? 0) - maxZ) < 1e-9)
    }

    @Test func aCircularEdgeMovesAlongItsAxisAndSidewaysIsRefused() throws {
        var document = DesignDocument.empty()
        _ = try document.createExtrudedCircle(
            name: "Cylinder", plane: .xy, center: SketchPoint(x: .length(0, .meter), y: .length(0, .meter)),
            radius: .length(0.02, .meter), depth: .length(0.05, .meter), direction: .normal
        )
        let circles = try edges(of: document).filter { $0.curveKind == "circle" }
        let top = try #require(circles.max { ($0.curveCenter?.z ?? 0) < ($1.curveCenter?.z ?? 0) })
        let target = try #require(top.selectionTarget())
        let topZ = try #require(top.curveCenter?.z)

        // The kernel refuses the sideways move when the store evaluates the candidate, and the
        // store restores the document.
        let store = CADDocumentStore(document: document)
        store.evaluateCurrentDocument()
        #expect(throws: EditorError.self) {
            try store.apply(.moveBodyEdges(targets: [target], direction: .unitX, distance: .length(0.01, .meter)))
        }
        #expect(store.document.cadDocument.designGraph == document.cadDocument.designGraph)
        #expect(store.evaluationStatus == .valid)

        try document.moveBodyEdges(targets: [target], direction: .unitZ, distance: .length(0.01, .meter))
        let moved = try edges(of: document).filter { $0.curveKind == "circle" }
        #expect(moved.contains { abs(($0.curveCenter?.z ?? 0) - (topZ + 0.01)) < 1e-9 && abs(($0.curveRadius ?? 0) - 0.02) < 1e-9 })
    }
}
