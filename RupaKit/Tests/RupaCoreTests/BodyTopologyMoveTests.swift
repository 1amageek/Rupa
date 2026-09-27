import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

/// Move Faces and Move Vertices append the kernel's face and vertex moves and keep the selection
/// on the moved targets.
@Suite struct BodyTopologyMoveTests {
    private func box() throws -> DesignDocument {
        var document = DesignDocument.empty()
        _ = try document.createExtrudedRectangle(
            name: "Box", plane: .xy, width: .length(0.1, .meter), height: .length(0.1, .meter),
            depth: .length(0.1, .meter), direction: .normal
        )
        return document
    }

    private func entries(_ kind: TopologySummaryResult.Entry.Kind, of document: DesignDocument) throws -> [TopologySummaryResult.Entry] {
        try TopologySnapshotService().snapshot(document: document).entries.filter { $0.kind == kind }
    }

    private func volume(of document: DesignDocument) throws -> Double {
        let evaluated = try DocumentEvaluator.modelingDefault(for: document).evaluateExact(document.cadDocument)
        return try evaluated.brep.volume(tolerance: document.modelingSettings.tolerance)
    }

    @Test func aTopFaceMovesUpAndTheSelectionFollowsIt() throws {
        var document = try box()
        let before = try volume(of: document)
        let faces = try entries(.face, of: document)
        let maxZ = faces.compactMap { $0.center?.z }.max() ?? 0
        let top = try #require(faces.first { abs(($0.center?.z ?? -1) - maxZ) < 1e-9 })
        let target = try #require(top.selectionTarget())

        try document.moveBodyFaces(targets: [target], direction: .unitZ, distance: .length(0.02, .meter))
        let moveID = try #require(document.cadDocument.designGraph.order.last)
        guard case .faceMove = document.cadDocument.designGraph.nodes[moveID]?.operation else {
            Issue.record("Expected a face move feature.")
            return
        }
        #expect(abs(try volume(of: document) - before * 1.2) < 1e-12)
        let moved = try #require(try document.topologyTargets(following: [target], to: moveID).first)
        let movedEntry = try #require(try entries(.face, of: document).first { $0.selectionTarget() == moved })
        #expect(abs((movedEntry.center?.z ?? 0) - (maxZ + 0.02)) < 1e-9)
    }

    @Test func aCornerVertexMovesAndAWarpingMoveIsKept() throws {
        var document = try box()
        let vertices = try entries(.vertex, of: document)
        let corner = try #require(vertices.max { lhs, rhs in
            let a = lhs.center ?? lhs.start, b = rhs.center ?? rhs.start
            return ((a?.x ?? 0) + (a?.y ?? 0) + (a?.z ?? 0)) < ((b?.x ?? 0) + (b?.y ?? 0) + (b?.z ?? 0))
        })
        let target = try #require(corner.selectionTarget())
        let before = document

        try document.moveBodyVertices(targets: [target], direction: Vector3D(x: 1, y: 1, z: 1), distance: .length(0.01, .meter))
        let moveID = try #require(document.cadDocument.designGraph.order.last)
        guard case .vertexMove = document.cadDocument.designGraph.nodes[moveID]?.operation else {
            Issue.record("Expected a vertex move feature.")
            return
        }
        #expect(document.cadDocument.designGraph.order.count == before.cadDocument.designGraph.order.count + 1)
        #expect(try volume(of: document) > (try volume(of: before)))
    }

    @Test func aMoveOnAnotherKindOfTargetIsRefused() throws {
        var document = try box()
        let edge = try #require(try entries(.edge, of: document).first?.selectionTarget())
        let before = document
        #expect(throws: EditorError.self) {
            try document.moveBodyFaces(targets: [edge], direction: .unitZ, distance: .length(0.01, .meter))
        }
        #expect(document.cadDocument.designGraph == before.cadDocument.designGraph)
    }
}
