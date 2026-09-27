import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

/// A sketch presented by a moved scene node offers its snap points where the scene draws it.
@Suite struct SnapPlacedSketchTests {
    private func point(_ x: Double, _ y: Double) -> SketchPoint {
        SketchPoint(x: .length(x, .meter), y: .length(y, .meter))
    }

    private func candidates(near point: Point2D, in document: DesignDocument, plane: SketchPlane?) throws -> [SnapCandidate] {
        try SnapResolver().resolve(
            point: point, in: document, ruler: .standard(for: .millimeter),
            options: SnapResolutionOptions(
                usesGrid: false, usesObjects: true, constructionPlane: plane, gridIntervalMeters: 0.001,
                objectSearchRadiusMeters: 0.01, maximumCandidateCount: 32
            )
        ).candidates
    }

    @Test func aMovedLineSnapsAtItsDrawnEnds() throws {
        var document = DesignDocument.empty()
        let featureID = try document.createLineSketch(name: "Line", plane: .xy, start: point(0, 0), end: point(0.1, 0))
        let node = try #require(document.productMetadata.sceneNodes.values.first { $0.reference?.featureID == featureID }).id
        try document.transformSceneNodes(ids: [node], worldDelta: try .translation(Vector3D(x: 1, y: 0.5, z: 0)))

        for plane: SketchPlane? in [nil, .xy] {
            let drawn = try candidates(near: Point2D(x: 1.1, y: 0.501), in: document, plane: plane)
            let end = try #require(drawn.first { $0.kind == .lineEnd })
            #expect(abs(end.point.x - 1.1) < 1e-12 && abs(end.point.y - 0.5) < 1e-12)
            let authored = try candidates(near: Point2D(x: 0.1, y: 0.001), in: document, plane: plane)
            #expect(!authored.contains { $0.kind == .lineEnd }, "Nothing snaps at the unplaced source position.")
        }
    }

    @Test func aRotatedArcStaysAnExactArc() throws {
        var document = DesignDocument.empty()
        let arcID = try document.createArcSketch(
            name: "Arc", plane: .xy, center: point(0, 0), radius: .length(1, .meter),
            startAngle: .angle(0, .radian), endAngle: .angle(.pi / 2, .radian)
        )
        let arcNode = try #require(document.productMetadata.sceneNodes.values.first { $0.reference?.featureID == arcID }).id
        // A quarter turn carries the arc's start from (1, 0) to (0, 1).
        try document.transformSceneNodes(
            ids: [arcNode], worldDelta: try Transform3D.rotation(axis: .unitZ, angleRadians: .pi / 2, about: .origin)
        )
        let start = try #require(try candidates(near: Point2D(x: 0.001, y: 1), in: document, plane: .xy).first { $0.kind == .arcStart })
        #expect(abs(start.point.x) < 1e-9 && abs(start.point.y - 1) < 1e-9)
        let closest = try candidates(near: Point2D(x: -0.7071, y: 0.7072), in: document, plane: .xy).first { $0.kind == .arcClosest }
        #expect(closest.map { abs(hypot($0.point.x, $0.point.y) - 1) < 1e-9 } == true, "The closest point lies on the exact arc.")
    }
}
