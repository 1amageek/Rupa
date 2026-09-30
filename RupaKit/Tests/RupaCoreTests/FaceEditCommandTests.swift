import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

/// Push Face, Draft Face and Match Face reshape an object where it is shown, keeping its place and
/// name: several faces, or one with an adjacent angle, push through Swift-CAD's face offset; a
/// face matches another object's face where that object is shown.
@MainActor
@Suite struct FaceEditCommandTests {
    private func box(_ session: EditorSession, _ name: String, height: Double = 0.1) throws -> SceneNodeID {
        _ = try session.execute(.createExtrudedRectangle(
            name: name, plane: .xy,
            width: .length(0.1, .meter), height: .length(0.1, .meter),
            depth: .length(height, .meter), direction: .normal
        ))
        return try #require(session.document.productMetadata.sceneNodes.values.first {
            $0.name.hasPrefix(name) && $0.reference?.kind == .body
        }).id
    }

    private func faces(of node: SceneNodeID, in session: EditorSession) throws -> [TopologySummaryResult.Entry] {
        try TopologySnapshotService().snapshot(document: session.document).entries
            .filter { $0.kind == .face && $0.sceneNodeID == node.description }
    }

    private func face(of node: SceneNodeID, in session: EditorSession, normal: Vector3D, extreme: (Point3D) -> Double) throws -> SelectionTarget {
        let candidates = try faces(of: node, in: session).filter {
            guard let n = $0.surfaceNormal else { return false }
            return n.x * normal.x + n.y * normal.y + n.z * normal.z > 0.99
        }
        let best = try #require(candidates.max { extreme(Point3D(x: $0.center?.x ?? 0, y: $0.center?.y ?? 0, z: $0.center?.z ?? 0)) < extreme(Point3D(x: $1.center?.x ?? 0, y: $1.center?.y ?? 0, z: $1.center?.z ?? 0)) })
        return try #require(best.selectionTarget())
    }

    private func volume(_ session: EditorSession) throws -> Double {
        try MeasurementService().measure(document: session.document, ruler: .standard(for: .meter)).totals.solidVolumeCubicMeters
    }

    @Test(.timeLimit(.minutes(1)))
    func severalFacesPushTogetherThroughTheKernel() throws {
        let session = EditorSession()
        let target = try box(session, "Box")
        let top = try face(of: target, in: session, normal: Vector3D(x: 0, y: 0, z: 1)) { $0.z }
        let side = try face(of: target, in: session, normal: Vector3D(x: 1, y: 0, z: 0)) { $0.x }
        _ = try session.execute(.pushFaces(targets: [top, side], distance: .length(0.01, .meter)))
        #expect(abs(try volume(session) - 0.11 * 0.1 * 0.11) < 1e-12)
        #expect(session.document.productMetadata.sceneNodes[target]?.name.hasPrefix("Box") == true)
        #expect(session.evaluationStatus == .valid)
    }

    @Test(.timeLimit(.minutes(1)))
    func anAdjacentAngleTiltsTheWallsBesideAPushedTop() throws {
        let session = EditorSession()
        _ = try box(session, "Box")
        let target = try #require(session.document.productMetadata.sceneNodes.values.first { $0.reference?.kind == .body }).id
        let top = try face(of: target, in: session, normal: Vector3D(x: 0, y: 0, z: 1)) { $0.z }
        _ = try session.execute(.pushFaces(targets: [top], distance: .length(0.01, .meter), adjacentAngle: .angle(5, .degree)))
        // Each wall turns about its top edge, so above it the body grows and below it shrinks.
        let t = tan(5 * Double.pi / 180)
        let volume = try volume(session)
        let integrated = (0..<2_000).reduce(0.0) { sum, index in
            let z = (Double(index) + 0.5) * 0.11 / 2_000
            let side = 0.1 + 2 * (z - 0.1) * t
            return sum + side * side * 0.11 / 2_000
        }
        #expect(abs(volume - integrated) < 1e-9)
        #expect(session.evaluationStatus == .valid)
    }

    @Test(.timeLimit(.minutes(1)))
    func aTopMatchesAnotherObjectsTopWhereItIsShown() throws {
        let session = EditorSession()
        let short = try box(session, "Short")
        let tall = try box(session, "Tall")
        _ = try session.execute(.setSceneNodeTransform(id: tall, localTransform: try Transform3D.translation(Vector3D(x: 0.3, y: 0, z: 0.02))))
        let top = try face(of: short, in: session, normal: Vector3D(x: 0, y: 0, z: 1)) { $0.z }
        let reference = try face(of: tall, in: session, normal: Vector3D(x: 0, y: 0, z: 1)) { $0.z }
        _ = try session.execute(.matchFaces(targets: [top], reference: reference))
        // The tall box is shown 2 cm higher, so the short one's top rises to 12 cm.
        #expect(abs(try volume(session) - (0.1 * 0.1 * 0.12 + 0.1 * 0.1 * 0.1)) < 1e-12)
        #expect(session.evaluationStatus == .valid)
    }
}
