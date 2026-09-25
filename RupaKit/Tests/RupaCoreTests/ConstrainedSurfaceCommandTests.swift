import Foundation
import Testing
import SwiftCAD
@testable import RupaCore

@MainActor
@Suite("Constrained Surface commands", .timeLimit(.minutes(1)))
struct ConstrainedSurfaceCommandTests {
    @Test func creationReplacementReplayAndFailureAreAtomic() throws {
        let session = EditorSession()
        var source = ConstrainedSurfaceFeature(points: [
            .init(position: .origin),
            .init(position: Point3D(x: 0.1, y: 0, z: 0)),
            .init(position: Point3D(x: 0, y: 0.1, z: 0)),
            .init(position: Point3D(x: 0.04, y: 0.04, z: 0.01)),
        ], positionTolerance: 1e-7, angularTolerance: 1e-4)
        let command = EditorCommand.createConstrainedSurface(name: "Points", source: source)
        #expect(try JSONDecoder().decode(EditorCommand.self, from: JSONEncoder().encode(command)) == command)
        _ = try session.execute(command)
        #expect(session.evaluationStatus == .valid)
        let original = session.document
        let id = try #require(original.cadDocument.designGraph.order.last)
        let output = try #require(original.cadDocument.designGraph.nodes[id]).outputs
        source.points[3].position.z = 0.02
        _ = try session.execute(.setConstrainedSurface(featureID: id, source: source))
        #expect(session.evaluationStatus == .valid)
        #expect(session.document.cadDocument.designGraph.nodes[id]?.outputs == output)
        #expect(session.document.productMetadata == original.productMetadata)
        let edited = session.document
        let replay = try JSONDecoder().decode(CADDocument.self, from: JSONEncoder().encode(edited.cadDocument))
        let result = try DocumentEvaluator.modelingDefault(for: edited).evaluateExact(replay)
        #expect(result.brep.bodies.values.first?.kind == .sheet)
        _ = try session.undo()
        #expect(session.document.cadDocument.designGraph.nodes[id] == original.cadDocument.designGraph.nodes[id])
        _ = try session.redo()
        #expect(session.document.cadDocument.designGraph.nodes[id] == edited.cadDocument.designGraph.nodes[id])
        source.points = (0..<3).map { .init(position: Point3D(x: Double($0), y: 0, z: 0)) }
        #expect(throws: (any Error).self) {
            try session.execute(.setConstrainedSurface(featureID: id, source: source))
        }
        #expect(session.document.cadDocument.designGraph.nodes[id] == edited.cadDocument.designGraph.nodes[id])
        #expect(session.document.productMetadata == edited.productMetadata)
    }
}
