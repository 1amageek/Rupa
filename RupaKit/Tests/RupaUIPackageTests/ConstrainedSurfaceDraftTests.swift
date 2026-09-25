import Testing
import RupaCore
@testable import RupaUI

@Suite("Constrained Surface draft", .timeLimit(.minutes(1)))
struct ConstrainedSurfaceDraftTests {
    @Test func pointsUndoOptionsAndReplacementUseTheSameSource() throws {
        var document = DesignDocument.empty()
        var draft = ModelingOperationDraft(kind: .constrainedSurface,
            selection: SelectionModel(), ruler: .standard(for: .millimeter))
        #expect(throws: (any Error).self) { try draft.command(in: document) }
        for point in [Point3D.origin, Point3D(x: 0.1, y: 0, z: 0), Point3D(x: 0, y: 0.1, z: 0)] {
            try draft.appendWorldPoint(point, in: document)
        }
        draft.origin = ["20 mm", "30 mm", "10 mm"]
        try draft.appendCoordinatePoint()
        #expect(draft.constrainedPoints.last?.position == Point3D(x: 0.02, y: 0.03, z: 0.01))
        draft.undoConstrainedPoint()
        draft.pointOptimization = .performance
        guard case let .createConstrainedSurface(name, source) = try draft.command(in: document) else {
            Issue.record("Expected constrained source creation"); return
        }
        #expect(source.points.count == 3)
        #expect(source.optimization == .performance)
        let id = try document.createConstrainedSurface(name: name, source: source)
        let node = try #require(document.productMetadata.sceneNodes.values.first { $0.reference == .body(id) })
        document.productMetadata.sceneNodes[node.id]?.localTransform = try .translation(Vector3D(x: 1, y: 2, z: 3))
        draft.constrainedFeatureID = id
        draft.constrainedSceneNodeID = node.id
        try draft.appendWorldPoint(Point3D(x: 1.02, y: 2.03, z: 3.01), in: document)
        let added = try #require(draft.constrainedPoints.last).position
        #expect(abs(added.x - 0.02) < 1e-12 && abs(added.y - 0.03) < 1e-12 && abs(added.z - 0.01) < 1e-12)
        guard case let .setConstrainedSurface(target, replacement) = try draft.command(in: document) else {
            Issue.record("Expected source replacement"); return
        }
        #expect(target == id && replacement.points.count == 4)
        draft.angularTolerance = "0"
        #expect(throws: (any Error).self) { try draft.command(in: document) }
    }
}
