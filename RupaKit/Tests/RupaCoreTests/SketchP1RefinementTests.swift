import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

@Suite struct SketchP1RefinementTests {
    @Test(arguments: [1, 2, 3, 5], [false, true])
    func refinementTracksParameters(degree: Int, explicit: Bool) throws {
        var document = DesignDocument.empty()
        try document.upsertParameter(name: "height", expression: .length(0, .meter), kind: .length)
        let height = try ParameterExpressionParser().parse("height", parameters: document.cadDocument.parameters, targetKind: .length)
        let points = (0...(explicit ? 2 * degree : degree)).map { i in
            SketchPoint(x: .length(Double(i), .meter), y: .multiply(height, .scalar(Double(i % 3))))
        }
        let knots = Array(repeating: 2.0, count: degree + 1)
            + (1...degree).map { 2 + 3 * Double($0) / Double(degree + 1) }
            + Array(repeating: 5.0, count: degree + 1)
        let source = SketchSpline(controlPoints: points, degree: degree, knots: explicit ? knots : nil)
        let feature = try document.createSplineSketch(name: "Curve", plane: .xy, spline: source)
        guard case .sketch(let sketch) = document.cadDocument.designGraph.nodes[feature]?.operation else { Issue.record("Missing sketch"); return }
        let entity = try #require(sketch.entityOrder.first)
        let node = try #require(document.productMetadata.sceneNodes.values.first { $0.reference?.featureID == feature })
        let target = SelectionTarget(sceneNodeID: node.id, component: .sketchEntity(.sketchEntity(featureID: feature, entityID: entity)))
        var splitDocument = document
        let newEntity = try splitDocument.splitSketchCurve(target: target, fraction: .scalar(0.37))
        try document.raiseSketchCurveDegree(targets: [target])
        for value in [0.4, -0.2] {
            try document.upsertParameter(name: "height", expression: .length(value, .meter), kind: .length)
            try splitDocument.upsertParameter(name: "height", expression: .length(value, .meter), kind: .length)
            let expected = try document.resolvedSketchSplineCurve(source, owner: "Test")
            func curve(_ doc: DesignDocument, _ id: SketchEntityID) throws -> SketchSplineCurve {
                guard case .sketch(let edited) = doc.cadDocument.designGraph.nodes[feature]?.operation,
                      case .spline(let spline) = edited.entities[id] else { throw EditorError(code: .referenceUnresolved, message: "Missing spline") }
                let restored = try JSONDecoder().decode(SketchSpline.self, from: JSONEncoder().encode(spline))
                #expect(restored.controlPoints.contains { !$0.y.referencedParameterIDs.isEmpty })
                return try doc.resolvedSketchSplineCurve(restored, owner: "Test")
            }
            let raised = try curve(document, entity)
            let lower = try curve(splitDocument, entity)
            let upper = try curve(splitDocument, newEntity)
            #expect(raised.degree == degree + 1)
            for i in 0...40 {
                let f = Double(i) / 40
                let a = try expected.bSpline.point(at: expected.parameter(ofFraction: f), tolerance: .standard)
                let b = try raised.bSpline.point(at: raised.parameter(ofFraction: f), tolerance: .standard)
                let part = f <= 0.37 ? lower : upper
                let local = f <= 0.37 ? f / 0.37 : (f - 0.37) / 0.63
                let c = try part.bSpline.point(at: part.parameter(ofFraction: local), tolerance: .standard)
                #expect(hypot(a.x - b.x, a.y - b.y) < 1e-9)
                #expect(hypot(a.x - c.x, a.y - c.y) < 1e-9)
            }
        }
    }

    @Test func raisedLineAndSplitPointTrackEndpoint() throws {
        var document = DesignDocument.empty()
        try document.upsertParameter(name: "height", expression: .length(0, .meter), kind: .length)
        let height = try ParameterExpressionParser().parse("height", parameters: document.cadDocument.parameters, targetKind: .length)
        let start = SketchPoint(x: .length(0, .meter), y: .length(0, .meter))
        let end = SketchPoint(x: .length(2, .meter), y: height)
        let feature = try document.createLineSketch(name: "Line", plane: .xy, start: start, end: end)
        guard case .sketch(let sketch) = document.cadDocument.designGraph.nodes[feature]?.operation else { Issue.record("Missing sketch"); return }
        let entity = try #require(sketch.entityOrder.first)
        let node = try #require(document.productMetadata.sceneNodes.values.first { $0.reference?.featureID == feature })
        let target = SelectionTarget(sceneNodeID: node.id, component: .sketchEntity(.sketchEntity(featureID: feature, entityID: entity)))
        let split = try document.splitPoint(on: SketchLine(start: start, end: end), fraction: 0.25, owner: "Test")
        try document.raiseSketchCurveDegree(targets: [target])
        try document.upsertParameter(name: "height", expression: .length(4, .meter), kind: .length)
        #expect(try document.resolvedSketchPoint(split, owner: "Test").y == 1)
        guard case .sketch(let changed) = document.cadDocument.designGraph.nodes[feature]?.operation,
              case .spline(let raised) = changed.entities[entity] else { Issue.record("Missing spline"); return }
        #expect(try document.resolvedSketchPoint(raised.controlPoints[1], owner: "Test").y == 2)
    }

    @Test func refinementRefusesInvalidDomainsAndPreservesClosure() throws {
        let points = [SketchPoint(x: .length(0, .meter), y: .length(0, .meter)), SketchPoint(x: .length(1, .meter), y: .length(1, .meter))]
        let source = SketchSpline(controlPoints: points, degree: 1)
        let refinement = SketchSplineRefinement()
        for parameter in [0.0, 1.0, -Double.infinity, Double.nan] {
            #expect(throws: Error.self) { try refinement.split(source, at: parameter) }
        }
        let closed = SketchSpline(controlPoints: points + [points[0]], isClosed: true, degree: 1)
        #expect(try refinement.degreeElevated(closed).isClosed)
        #expect(throws: Error.self) { try refinement.split(closed, at: 0.5) }
    }
}
