import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

/// Imprint, Isoparam, Untrim and the offsets split faces of objects where they are shown, each
/// object keeping its place and name.
@MainActor
@Suite struct ImprintCommandTests {
    private func box(_ session: EditorSession, _ name: String, size: Double = 0.1) throws -> SceneNodeID {
        _ = try session.execute(.createExtrudedRectangle(
            name: name, plane: .xy,
            width: .length(size, .meter), height: .length(size, .meter),
            depth: .length(size, .meter), direction: .normal
        ))
        return try #require(session.document.productMetadata.sceneNodes.values.first {
            $0.name.hasPrefix(name) && $0.reference?.kind == .body
        }).id
    }

    private func entries(_ kind: TopologySummaryResult.Entry.Kind, of node: SceneNodeID, in session: EditorSession) throws -> [TopologySummaryResult.Entry] {
        try TopologySnapshotService().snapshot(document: session.document).entries
            .filter { $0.kind == kind && $0.sceneNodeID == node.description }
    }

    private func top(of node: SceneNodeID, in session: EditorSession) throws -> SelectionTarget {
        let faces = try entries(.face, of: node, in: session)
        let heights = faces.map { $0.center?.z ?? -.infinity }
        let highest = try #require(heights.max())
        return try #require(faces.first { ($0.center?.z ?? -.infinity) == highest && abs($0.surfaceNormal?.z ?? 0) > 0.5 }?.selectionTarget())
    }

    @Test(.timeLimit(.minutes(1)))
    func aToolImprintsTheTargetWhereItIsShownAndCanBeImprintedBack() throws {
        let session = EditorSession()
        let target = try box(session, "Target")
        let tool = try box(session, "Tool", size: 0.04)
        // The small box is shown standing through the target's top, away from its edges.
        _ = try session.execute(.setSceneNodeTransform(id: tool, localTransform: try Transform3D.translation(Vector3D(x: 0.02, y: 0.02, z: 0.08))))
        _ = try session.execute(.imprintBodies(name: "Imprint", target: target, tool: tool, targetCompletion: .none, imprintsTool: true, toolCompletion: .none))
        #expect(try entries(.face, of: target, in: session).count == 7)
        // The tool's four sides are each cut where they pass through the target's top.
        #expect(try entries(.face, of: tool, in: session).count == 10)
        #expect(session.document.productMetadata.sceneNodes[target]?.name == "Target")
        #expect(session.evaluationStatus == .valid)
    }

    @Test(.timeLimit(.minutes(1)))
    func curvesImprintWhereTheyAndTheTargetAreShown() throws {
        let session = EditorSession()
        let target = try box(session, "Target")
        _ = try session.execute(.setSceneNodeTransform(id: target, localTransform: try Transform3D.translation(Vector3D(x: 0, y: 0, z: 0.2))))
        _ = try session.execute(.createCircleSketch(
            name: "Circle", plane: .xy,
            center: SketchPoint(x: .length(0, .meter), y: .length(0, .meter)), radius: .length(0.02, .meter)
        ))
        let circle = try #require(try SketchEntitySnapshotService().snapshot(document: session.document).entries.first { $0.entityKind == "circle" })
        _ = try session.execute(.imprintCurves(
            name: "Imprint", target: target, curves: [try #require(circle.selectionTarget())],
            projection: .vector(direction: Vector3D(x: 0, y: 0, z: 1), bidirectional: false, hidesOcclusion: true), completion: .none
        ))
        // The circle lands on the bottom the box shows above it, as a disc.
        #expect(try entries(.face, of: target, in: session).count == 7)
        #expect(session.evaluationStatus == .valid)
    }

    @Test(.timeLimit(.minutes(1)))
    func isoparamAndOffsetsSplitFacesInPlace() throws {
        let session = EditorSession()
        let target = try box(session, "Target")
        _ = try session.execute(.isoparam(name: "Isoparam", face: try top(of: target, in: session), direction: .u, fractions: [0.5], subdividesControlNet: false))
        #expect(try entries(.face, of: target, in: session).count == 7)
        // Offset Face Loop on both halves of the top together offsets their shared outline only.
        let halves = try entries(.face, of: target, in: session).filter { ($0.center?.z ?? 0) > 0.09 && abs($0.surfaceNormal?.z ?? 0) > 0.5 }
        #expect(halves.count == 2)
        _ = try session.execute(.offsetFaceLoops(
            name: "Offset Face Loop", targets: halves.compactMap { $0.selectionTarget() }, distance: .length(0.01, .meter),
            isSymmetric: false, gapFill: .round, isIndividual: false
        ))
        #expect(try entries(.face, of: target, in: session).count == 9)
        #expect(session.evaluationStatus == .valid)
        #expect(abs(try MeasurementService().measure(document: session.document, ruler: .standard(for: .meter)).totals.solidVolumeCubicMeters - 0.001) < 1e-9)
    }

    @Test(.timeLimit(.minutes(1)))
    func severalEdgesOffsetOverTheirFace() throws {
        let session = EditorSession()
        let target = try box(session, "Target")
        let topFace = try top(of: target, in: session)
        let topEdges = try entries(.edge, of: target, in: session).filter { ($0.start?.z ?? 0) > 0.09 && ($0.end?.z ?? 0) > 0.09 }
        let chosen = Array(topEdges.prefix(2)).compactMap { $0.selectionTarget() }
        #expect(chosen.count == 2)
        _ = try session.execute(.offsetEdges(
            name: "Offset Edge", targets: chosen, supportFace: topFace, distance: .length(0.01, .meter), isSymmetric: false, gapFill: .round
        ))
        #expect(try entries(.face, of: target, in: session).count >= 7)
        #expect(session.evaluationStatus == .valid)
        // A face the edges do not bound is refused with nothing changed.
        let before = session.document.cadDocument.designGraph
        let bottomEdge = try #require(try entries(.edge, of: target, in: session).first { ($0.start?.z ?? 1) < 0.01 && ($0.end?.z ?? 1) < 0.01 }?.selectionTarget())
        #expect(throws: EditorError.self) {
            _ = try session.execute(.offsetEdges(
                name: "Offset Edge", targets: [bottomEdge], supportFace: try top(of: target, in: session),
                distance: .length(0.01, .meter), isSymmetric: false, gapFill: .round
            ))
        }
        #expect(session.document.cadDocument.designGraph == before)

        // A negative distance offsets over the face across the edge: the wall below a top edge.
        let other = EditorSession()
        let box = try self.box(other, "Box")
        let edge = try #require(try entries(.edge, of: box, in: other).first { ($0.start?.z ?? 0) > 0.09 && ($0.end?.z ?? 0) > 0.09 }?.selectionTarget())
        let topZ = try #require(try entries(.edge, of: box, in: other).compactMap { $0.start?.z }.max())
        _ = try other.execute(.offsetEdges(
            name: "Offset Edge", targets: [edge], supportFace: try top(of: box, in: other), distance: .length(-0.01, .meter),
            isSymmetric: false, gapFill: .round
        ))
        #expect(other.evaluationStatus == .valid)
        #expect(try entries(.edge, of: box, in: other).contains { entry in
            guard let start = entry.start, let end = entry.end else { return false }
            return abs(start.z - (topZ - 0.01)) < 1e-9 && abs(end.z - (topZ - 0.01)) < 1e-9
        })
    }

    @Test(.timeLimit(.minutes(1)))
    func untrimMakesASheetBesideTheObjectAndOpensIt() throws {
        let session = EditorSession()
        let target = try box(session, "Target")
        _ = try session.execute(.setSceneNodeTransform(id: target, localTransform: try Transform3D.translation(Vector3D(x: 0.3, y: 0, z: 0))))
        let topFace = try top(of: target, in: session)
        let topCenter = try #require(try entries(.face, of: target, in: session).first { $0.selectionTarget() == topFace }?.center)
        _ = try session.execute(.untrimFace(name: "Untrim", face: topFace, keepsEdges: false))
        let sheet = try #require(session.document.productMetadata.sceneNodes.values.first {
            $0.id != target && $0.reference?.kind == .body && $0.object?.geometryRole == .surface
        })
        #expect(try entries(.face, of: sheet.id, in: session).count == 1)
        // The box loses its top, left open as a sheet of its other five faces.
        #expect(session.document.productMetadata.sceneNodes[target]?.object?.geometryRole == .surface)
        #expect(try entries(.face, of: target, in: session).count == 5)
        #expect(session.evaluationStatus == .valid)
        // Placed like the box, the sheet lies where its top was.
        let sheetCenter = try #require(try entries(.face, of: sheet.id, in: session).first?.center)
        #expect(abs(sheetCenter.x - topCenter.x) < 1e-9 && abs(sheetCenter.y - topCenter.y) < 1e-9 && abs(sheetCenter.z - topCenter.z) < 1e-9)
    }
}
