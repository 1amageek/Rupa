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

/// Several targets move, rotate or scale together through one kernel topology transform.
@Suite struct BodyTopologyTransformTests {
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

    @Test func twoEdgesSharingACornerMoveItOnce() throws {
        var document = try box()
        let edges = try entries(.edge, of: document)
        let maxZ = edges.compactMap { $0.midpoint?.z }.max() ?? 0
        let maxX = edges.compactMap { $0.midpoint?.x }.max() ?? 0
        let maxY = edges.compactMap { $0.midpoint?.y }.max() ?? 0
        // The top edges on the +X and +Y sides meet at one corner.
        let chosen = edges.filter { entry in
            guard let mid = entry.midpoint, abs(mid.z - maxZ) < 1e-9 else { return false }
            return abs(mid.x - maxX) < 1e-9 || abs(mid.y - maxY) < 1e-9
        }
        #expect(chosen.count == 2)
        try document.moveBodyEdges(
            targets: chosen.compactMap { $0.selectionTarget() }, direction: .unitZ, distance: .length(0.01, .meter)
        )
        guard case .topologyTransform = document.cadDocument.designGraph.nodes[document.cadDocument.designGraph.order.last!]?.operation else {
            Issue.record("Several targets move through one topology transform.")
            return
        }
        let heights = try entries(.vertex, of: document).compactMap { $0.start?.z }
        #expect(heights.filter { abs($0 - (maxZ + 0.01)) < 1e-9 }.count == 3)
        #expect(!heights.contains { $0 > maxZ + 0.0101 })
    }

    @Test func aTopFaceTurnsAboutItsMiddle() throws {
        var document = try box()
        let faces = try entries(.face, of: document)
        let maxZ = faces.compactMap { $0.center?.z }.max() ?? 0
        let top = try #require(faces.first { abs(($0.center?.z ?? -1) - maxZ) < 1e-9 })
        let center = try #require(top.center)
        try document.transformBodyTopology(
            .faces, targets: [try #require(top.selectionTarget())],
            motion: .rotation(DirectRotation(
                origin: Point3D(x: center.x, y: center.y, z: center.z), axis: .unitY, angle: .angle(10, .degree)
            ))
        )
        let moveID = try #require(document.cadDocument.designGraph.order.last)
        #expect(document.cadDocument.designGraph.nodes[moveID]?.name == "Rotate Faces")
        let heights = try entries(.vertex, of: document).compactMap { $0.start?.z }
        #expect((heights.max() ?? 0) > maxZ + 0.008)
    }
}
