import Foundation
import RupaCore
import SwiftCAD
import Testing
@testable import RupaUI

/// Complete Edge and Subdivide find the curves and surfaces in the selection.
@Suite struct WorkspaceCurveRefinementPlannerTests {
    private func point(_ x: Double, _ y: Double) -> SketchPoint {
        SketchPoint(x: .length(x, .meter), y: .length(y, .meter))
    }

    @Test func selectedCurveObjectsAndSurfacesBecomeTheirCommands() throws {
        var document = DesignDocument.empty()
        let line = try document.createLineSketch(name: "Line", plane: .xy, start: point(0, 0), end: point(1, 0))
        let spline = try document.createSplineSketch(name: "Spline", plane: .xy, spline: SketchSpline(
            controlPoints: [point(0, 0), point(1, 1), point(2, 1), point(3, 0)], isClosed: false
        ))
        let circle = try document.createCircleSketch(name: "Circle", plane: .xy, center: point(0, 0), radius: .length(1, .meter))
        let surface = try document.createBSplineSurface(name: "Surface", surface: BSplineSurface3D(
            uDegree: 1, vDegree: 1, uKnots: [0, 0, 1, 1], vKnots: [0, 0, 1, 1],
            controlPoints: [[.origin, Point3D(x: 1, y: 0, z: 0)], [Point3D(x: 0, y: 1, z: 0), Point3D(x: 1, y: 1, z: 0)]]
        ))
        func node(_ featureID: FeatureID) throws -> SceneNodeID {
            try #require(document.productMetadata.sceneNodes.values.first { $0.reference?.featureID == featureID }).id
        }
        let targets = try [line, spline, circle, surface].map { SelectionTarget(sceneNodeID: try node($0)) }
        let planner = WorkspaceCurveRefinementPlanner(document: document)

        let complete = planner.completeEdgeCommands(for: targets)
        #expect(complete.count == 2, "The line and the spline; a circle has no ends.")
        #expect(complete.allSatisfy { $0.name == "completeSketchCurve" })

        let subdivision = try planner.subdivision(for: targets)
        #expect(subdivision.commands.map(\.name) == ["subdivideSketchSpline", "subdivideSurface"])
        guard case .sketch(let sketch) = document.cadDocument.designGraph.nodes[spline]?.operation,
              let entityID = sketch.entityOrder.first else {
            Issue.record("Expected the spline sketch.")
            return
        }
        #expect(subdivision.createdControlPoints == [2, 3, 4].map { index in
            SelectionTarget(sceneNodeID: targets[1].sceneNodeID, component: .sketchEntity(.sketchControlPoint(
                featureID: spline, entityID: entityID, index: index
            )))
        })
        #expect(try planner.subdivision(for: [targets[0], targets[2]]).commands.isEmpty)
    }
}

@MainActor
@Test func completeEdgeFromASelectedLineObjectRunsThroughTheEditorSession() throws {
    let session = EditorSession()
    func point(_ x: Double, _ y: Double) -> SketchPoint { SketchPoint(x: .length(x, .meter), y: .length(y, .meter)) }
    var document = session.document
    let short = try document.createLineSketch(name: "Short", plane: .xy, start: point(0, 0.3), end: point(0.1, 0.3))
    _ = try document.createLineSketch(name: "Wall", plane: .xy, start: point(0.3, 0.2), end: point(0.3, 0.4))
    let loaded = EditorSession(document: document)
    let node = try #require(loaded.document.productMetadata.sceneNodes.values.first { $0.reference?.featureID == short }).id
    let commands = WorkspaceCurveRefinementPlanner(document: loaded.document)
        .completeEdgeCommands(for: [SelectionTarget(sceneNodeID: node)])
    #expect(commands.count == 1)
    for command in commands { _ = try loaded.execute(command) }
    guard case .sketch(let sketch) = loaded.document.cadDocument.designGraph.nodes[short]?.operation,
          let entityID = sketch.entityOrder.first, case .line(let line) = sketch.entities[entityID] else {
        Issue.record("Expected the line.")
        return
    }
    #expect(abs(try loaded.document.cadDocument.parameters.resolvedValue(for: line.end.x).value - 0.3) < 1e-9)
    _ = session
}
