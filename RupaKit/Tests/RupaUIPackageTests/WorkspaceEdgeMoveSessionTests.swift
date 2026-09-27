import Foundation
import RupaCore
import SwiftCAD
import Testing
@testable import RupaUI

/// Move on selected edges: only Move applies, and a world motion becomes the kernel's edge move in
/// the body's own frame.
@Suite struct WorkspaceEdgeMoveSessionTests {
    @Test func aWorldMotionBecomesAnEdgeMoveInTheBodyFrame() throws {
        var document = DesignDocument.empty()
        let featureID = try document.createExtrudedRectangle(
            name: "Box", plane: .xy, width: .length(0.1, .meter), height: .length(0.1, .meter),
            depth: .length(0.1, .meter), direction: .normal
        )
        let node = try #require(document.productMetadata.sceneNodes.values.first { $0.reference?.featureID == featureID }).id
        let edge = SelectionTarget(sceneNodeID: node, component: .edge(SelectionComponentID(rawValue: "edge")))
        var moving = WorkspaceTransformSession(sceneNodeIDs: [node], mode: .move)
        moving.topologyTargets = [edge]
        // The body is turned a quarter turn about Z, so world +Y is its own +X.
        moving.topologyBodyWorldTransform = try Transform3D.rotation(axis: .unitZ, angleRadians: .pi / 2, about: .origin)
        moving.pivotMode = .median
        try moving.resolveFrame(metadata: document.productMetadata, constructionPlane: nil, selectionBounds: nil)

        moving.press(mode: .rotate)
        #expect(moving.mode == .move, "Rotate does not apply to edges.")
        #expect(moving.gizmo(distanceStepMeters: 0.01) == nil)
        #expect(moving.title == "Move Edge")

        let command = try moving.command(worldDelta: try Transform3D.translation(Vector3D(x: 0, y: 0.01, z: 0)))
        guard case .moveBodyEdges(let targets, let direction, let distance) = command else {
            Issue.record("Expected an edge move.")
            return
        }
        #expect(targets == [edge])
        #expect((direction - .unitX).length < 1e-12)
        let meters = try document.cadDocument.parameters.resolvedValue(for: distance).value
        #expect(abs(meters - 0.01) < 1e-12)
        #expect(throws: EditorError.self) { try moving.command(worldDelta: .identity) }

        // The same session moves faces or vertices with their own direct edits.
        moving.topologyKind = .faces
        #expect(moving.title == "Move Face")
        guard case .moveBodyFaces = try moving.command(worldDelta: try Transform3D.translation(Vector3D(x: 0, y: 0.01, z: 0))) else {
            Issue.record("Expected a face move.")
            return
        }
        moving.topologyKind = .vertices
        guard case .moveBodyVertices = try moving.command(worldDelta: try Transform3D.translation(Vector3D(x: 0, y: 0.01, z: 0))) else {
            Issue.record("Expected a vertex move.")
            return
        }
    }
}
