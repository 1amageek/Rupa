import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

/// The curve commands read sketches and bodies where their scene placements put them: moving the
/// inputs moves the result with them.
@MainActor
@Suite struct WorldPlacedCurveCommandTests {
    private let shift = Vector3D(x: 0.1, y: 0.05, z: 0)

    private func box(_ document: inout DesignDocument, depth: Double = 10) throws -> SceneNodeID {
        let id = try document.createExtrudedRectangle(
            name: "Box", plane: .xy, width: .length(10, .millimeter), height: .length(10, .millimeter),
            depth: .length(depth, .millimeter), direction: .normal
        )
        return try #require(document.productMetadata.sceneNodes.first { $0.value.reference == .body(id) }?.key)
    }

    private func node(_ document: DesignDocument, _ featureID: FeatureID) throws -> SceneNodeID {
        try #require(document.productMetadata.sceneNodes.first { $0.value.reference?.featureID == featureID }?.key)
    }

    private func worldKnots(_ document: DesignDocument, _ id: FeatureID) throws -> [Point3D] {
        guard case .spatialPath(let path) = document.cadDocument.designGraph.nodes[id]?.operation else {
            throw EditorError(code: .referenceUnresolved, message: "The path is missing.")
        }
        let placement = try SceneNodeHierarchy(metadata: document.productMetadata).worldTransform(of: try node(document, id))
        return try path.knots.map { try placement.applied(to: $0.position) }
    }

    private func moved(_ points: [Point3D]) -> [Point3D] { points.map { $0 + shift } }

    /// The same points, in any order: a joined path may start at another of its pieces.
    private func same(_ a: [Point3D], _ b: [Point3D]) -> Bool {
        a.count == b.count
            && a.allSatisfy { p in b.contains { (p - $0).length < 1.0e-9 } }
            && b.allSatisfy { p in a.contains { (p - $0).length < 1.0e-9 } }
    }

    @Test func createOutlineFollowsAMovedBody() throws {
        var still = DesignDocument.empty()
        let stillBox = try box(&still)
        let stillID = try #require(try still.createBodyOutlines(targets: [SelectionTarget(sceneNodeID: stillBox)], plane: .xy).first)
        let expected = try worldKnots(still, stillID)

        var document = DesignDocument.empty()
        let body = try box(&document)
        try document.transformSceneNodes(ids: [body], worldDelta: .translation(shift))
        let resultID = try #require(try document.createBodyOutlines(targets: [SelectionTarget(sceneNodeID: body)], plane: .xy).first)
        let result = try worldKnots(document, resultID)
        #expect(same(result, moved(expected)))
    }

    @Test func projectOutlineFollowsAMovedBody() throws {
        var document = DesignDocument.empty()
        let body = try box(&document)
        try document.transformSceneNodes(ids: [body], worldDelta: .translation(shift))
        let id = try document.projectBodyOutlinesToConstructionPlane(targets: [SelectionTarget(sceneNodeID: body)], plane: .xy)
        let summary = try SketchEntitySnapshotService().snapshot(document: document)
        let lines = summary.entries.filter { $0.sourceFeatureID == id.description && $0.entityKind == "line" }
        #expect(lines.count == 4)
        // The box spans 10 mm from wherever the rectangle sketch put it, shifted by 100 mm in x.
        let xs = lines.flatMap { [$0.start?.x, $0.end?.x].compactMap { $0 } }
        #expect(xs.allSatisfy { $0 > 0.1 - 0.011 })
    }

    @Test func projectBodyBodyFollowsBodiesMovedTogetherAndRefusesBodiesMovedApart() throws {
        func twoBoxes(_ document: inout DesignDocument) throws -> (SceneNodeID, SceneNodeID) {
            let first = try box(&document, depth: 20)
            let secondID = try document.createExtrudedRectangleFromCorners(
                name: "Pierce", plane: .plane(Plane3D(origin: Point3D(x: 0, y: 0, z: 0.005), normal: .unitZ)),
                firstCorner: SketchPoint(x: .length(0, .millimeter), y: .length(0, .millimeter)),
                oppositeCorner: SketchPoint(x: .length(20, .millimeter), y: .length(20, .millimeter)),
                depth: .length(10, .millimeter), direction: .normal
            )
            return (first, try #require(document.productMetadata.sceneNodes.first { $0.value.reference == .body(secondID) }?.key))
        }
        var still = DesignDocument.empty()
        let (a, b) = try twoBoxes(&still)
        let stillID = try #require(try still.projectBodyIntersection(first: SelectionTarget(sceneNodeID: a), second: SelectionTarget(sceneNodeID: b)).first)
        let expected = try worldKnots(still, stillID)

        var document = DesignDocument.empty()
        let (c, d) = try twoBoxes(&document)
        try document.transformSceneNodes(ids: [c, d], worldDelta: .translation(shift))
        let resultID = try #require(try document.projectBodyIntersection(first: SelectionTarget(sceneNodeID: c), second: SelectionTarget(sceneNodeID: d)).first)
        let result = try worldKnots(document, resultID)
        #expect(same(result, moved(expected)))

        try document.transformSceneNodes(ids: [d], worldDelta: .translation(shift))
        #expect(throws: EditorError.self) {
            try document.projectBodyIntersection(first: SelectionTarget(sceneNodeID: c), second: SelectionTarget(sceneNodeID: d))
        }
    }

    @Test func projectCurveCurveFollowsMovedSketches() throws {
        func curves(_ document: inout DesignDocument) throws -> (SelectionTarget, SelectionTarget) {
            let top = try document.createLineSketch(
                name: "Top", plane: .xy,
                start: SketchPoint(x: .length(0, .millimeter), y: .length(5, .millimeter)),
                end: SketchPoint(x: .length(10, .millimeter), y: .length(5, .millimeter))
            )
            let side = try document.createLineSketch(
                name: "Side", plane: .zx,
                start: SketchPoint(x: .length(0, .millimeter), y: .length(-2, .millimeter)),
                end: SketchPoint(x: .length(8, .millimeter), y: .length(12, .millimeter))
            )
            func target(_ id: FeatureID) throws -> SelectionTarget {
                guard case .sketch(let sketch) = document.cadDocument.designGraph.nodes[id]?.operation,
                      let entity = sketch.entities.keys.first else { throw EditorError(code: .referenceUnresolved, message: "missing") }
                return SelectionTarget(sceneNodeID: try node(document, id), component: .sketchEntity(.sketchEntity(featureID: id, entityID: entity)))
            }
            return (try target(top), try target(side))
        }
        var still = DesignDocument.empty()
        let (a, b) = try curves(&still)
        let stillID = try still.projectCurveIntersection(first: a, second: b)
        let expected = try worldKnots(still, stillID)

        var document = DesignDocument.empty()
        let (c, d) = try curves(&document)
        try document.transformSceneNodes(ids: [c.sceneNodeID, d.sceneNodeID], worldDelta: .translation(shift))
        let resultID = try document.projectCurveIntersection(first: c, second: d)
        let result = try worldKnots(document, resultID)
        #expect(same(result, moved(expected)))
    }

    @Test func deformAndDirectionalProjectionFollowMovedInputs() throws {
        func scene(_ document: inout DesignDocument) throws -> (body: SceneNodeID, curve: SelectionTarget, bottom: SelectionTarget, side: SelectionTarget, top: SelectionTarget) {
            let body = try box(&document)
            let faces = try TopologySnapshotService().snapshot(document: document).entries.filter { $0.kind == .face }
            let bottom = try #require(faces.first { ($0.normal?.z ?? 0) < -0.5 })
            let side = try #require(faces.first { ($0.normal?.x ?? 0) > 0.5 })
            let top = try #require(faces.first { ($0.normal?.z ?? 0) > 0.5 })
            let center = try #require(bottom.center)
            let line = try document.createLineSketch(
                name: "Curve", plane: .xy,
                start: SketchPoint(x: .length(center.x - 0.002, .meter), y: .length(center.y - 0.001, .meter)),
                end: SketchPoint(x: .length(center.x + 0.003, .meter), y: .length(center.y + 0.001, .meter))
            )
            guard case .sketch(let sketch) = document.cadDocument.designGraph.nodes[line]?.operation,
                  let entity = sketch.entities.keys.first else { throw EditorError(code: .referenceUnresolved, message: "missing") }
            let curve = SelectionTarget(sceneNodeID: try node(document, line), component: .sketchEntity(.sketchEntity(featureID: line, entityID: entity)))
            return (body, curve, try #require(bottom.selectionTarget()), try #require(side.selectionTarget()), try #require(top.selectionTarget()))
        }
        var still = DesignDocument.empty()
        let a = try scene(&still)
        let stillDeform = try #require(try still.deformCurves(targets: [a.curve], referenceFace: a.bottom, targetFace: a.side,
                                                             options: CurveDeformationOptions(keepsTools: true)).first)
        let expectedDeform = try worldKnots(still, stillDeform)
        // Oblique so the top face is not met square on and the result is a path.
        let direction = Vector3D(x: 0.2, y: 0, z: 1)
        let stillProjection = try #require(try still.projectCurvesAlongDirection(targets: [a.curve], face: a.top, direction: direction, bidirectional: true).first)
        let expectedProjection = try worldKnots(still, stillProjection)

        var document = DesignDocument.empty()
        let b = try scene(&document)
        try document.transformSceneNodes(ids: [b.body, b.curve.sceneNodeID], worldDelta: .translation(shift))
        let deformID = try #require(try document.deformCurves(targets: [b.curve], referenceFace: b.bottom, targetFace: b.side,
                                                              options: CurveDeformationOptions(keepsTools: true)).first)
        #expect(same(try worldKnots(document, deformID), moved(expectedDeform)))
        let projectionID = try #require(try document.projectCurvesAlongDirection(targets: [b.curve], face: b.top, direction: direction, bidirectional: true).first)
        #expect(same(try worldKnots(document, projectionID), moved(expectedProjection)))
    }
}
