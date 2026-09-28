import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

@Suite struct PersistentCurveExtensionTests {
    private func point(_ x: Double, _ y: Double) -> SketchPoint {
        SketchPoint(x: .length(x, .meter), y: .length(y, .meter))
    }

    @Test func naturalExpressionEvaluatorsAndFailuresAgree() throws {
        let coordinates: [CADExpression] = [.length(0, .meter), .length(0, .meter), .length(1, .meter), .length(0, .meter)]
        let table = ParameterTable()
        let resolver = ParameterResolver()
        let resolved = try resolver.resolve(table)
        let expression = CADExpression.bezierNaturalExtension(coordinates: coordinates, length: .length(500, .millimeter), coordinateIndex: 0)
        #expect(try table.inferredKind(for: expression) == .length)
        #expect(abs(try table.resolvedValue(for: expression).value - 1.5) < 1e-10)
        #expect(abs(try resolver.evaluate(expression, parameters: resolved).value - 1.5) < 1e-10)
        let bad: [CADExpression] = [
            .bezierNaturalExtension(coordinates: coordinates, length: .scalar(1), coordinateIndex: 0),
            .bezierNaturalExtension(coordinates: coordinates, length: .length(0, .meter), coordinateIndex: 0),
            .bezierNaturalExtension(coordinates: coordinates, length: .length(.infinity, .meter), coordinateIndex: 0),
            .bezierNaturalExtension(coordinates: coordinates, length: .length(1, .meter), coordinateIndex: 2),
            .bezierNaturalExtension(coordinates: Array(repeating: .length(0, .meter), count: 4), length: .length(1, .meter), coordinateIndex: 0)
        ]
        for invalid in bad {
            #expect(throws: Error.self) { try table.resolvedValue(for: invalid) }
            #expect(throws: Error.self) { try resolver.evaluate(invalid, parameters: resolved) }
        }
        #expect(throws: Error.self) { try table.inferredKind(for: bad[0]) }
        for text in ["bezierNaturalExtension(0, 1m)", "bezierNaturalExtension(9, 1m, 0m, 0m, 1m, 0m)"] {
            #expect(throws: Error.self) { try ParameterExpressionParser().parse(text, parameters: table, targetKind: .length) }
        }
    }

    @Test(arguments: [false, true], [1, 3, 5])
    func naturalContinuationTracksShapeAndDistance(atStart: Bool, degree: Int) throws {
        for explicit in [false, true] {
            var document = DesignDocument.empty()
            try document.upsertParameter(name: "height", expression: .length(0, .meter), kind: .length)
            try document.upsertParameter(name: "extensionLength", expression: .length(0.3, .meter), kind: .length)
            let parse = ParameterExpressionParser()
            let height = try parse.parse("height", parameters: document.cadDocument.parameters, targetKind: .length)
            let length = try parse.parse("extensionLength", parameters: document.cadDocument.parameters, targetKind: .length)
            let points = (0...(2 * degree)).map { i in
                SketchPoint(x: .length(Double(i), .meter),
                    y: .add(.length(Double(i % 2) * 0.2, .meter), .multiply(height, .scalar(Double(i + 1)))))
            }
            let knots = Array(repeating: 0.0, count: degree + 1)
                + (1...degree).map { Double($0) / Double(degree + 1) }
                + Array(repeating: 1.0, count: degree + 1)
            let source = SketchSpline(controlPoints: points, degree: degree, knots: explicit ? knots : nil)
            let feature = try document.createSplineSketch(name: "Curve", plane: .xy, spline: source)
            guard case .sketch(let sketch) = document.cadDocument.designGraph.nodes[feature]?.operation else { Issue.record("Missing sketch"); return }
            let entity = try #require(sketch.entityOrder.first)
            let node = try #require(document.productMetadata.sceneNodes.values.first { $0.reference?.featureID == feature })
            let target = SelectionTarget(sceneNodeID: node.id, component: .sketchEntity(.sketchControlPoint(
                featureID: feature, entityID: entity, index: atStart ? 0 : points.count - 1)))
            try document.extendSketchCurve(target: target, distance: length, shape: .natural)
            try document.upsertParameter(name: "height", expression: .length(0.1, .meter), kind: .length)
            try document.upsertParameter(name: "extensionLength", expression: .length(0.6, .meter), kind: .length)
            guard case .sketch(let changed) = document.cadDocument.designGraph.nodes[feature]?.operation,
                  case .spline(let extended) = changed.entities[entity] else { Issue.record("Missing extension"); return }
            let roundTrip = try JSONDecoder().decode(SketchSpline.self, from: JSONEncoder().encode(extended))
            let oldCurve = try document.resolvedSketchSplineCurve(source, owner: "Test")
            let oldSegment = try #require(atStart ? oldCurve.segments.first : oldCurve.segments.last)
            let expected = try CubicBezierChainExtension(tolerance: .standard).naturalSpan(
                ofSegment: oldSegment.controlPoints, at: atStart ? .start : .end, length: 0.6)
            let actual = atStart ? Array(roundTrip.controlPoints.prefix(degree)) : Array(roundTrip.controlPoints.suffix(degree))
            for (point, expected) in zip(actual, expected) {
                let x = try document.cadDocument.parameters.resolvedValue(for: point.x).value
                let y = try document.cadDocument.parameters.resolvedValue(for: point.y).value
                #expect(hypot(x - expected.x, y - expected.y) < 1e-9)
                let text = ParameterExpressionFormatter().format(point.x, parameters: document.cadDocument.parameters)
                let parsed = try parse.parse(text, parameters: document.cadDocument.parameters, targetKind: .length)
                #expect(parsed == point.x)
                #expect(point.x.referencedParameterIDs == height.referencedParameterIDs.union(length.referencedParameterIDs))
            }
            try document.upsertParameter(name: "extensionLength", expression: .length(0, .meter), kind: .length)
            #expect(throws: Error.self) { try document.resolvedSketchSplineCurve(roundTrip, owner: "Invalid distance") }
        }
    }

    @Test(arguments: [false, true])
    func lineDirectionTracksParameters(atStart: Bool) throws {
        var document = DesignDocument.empty()
        try document.upsertParameter(name: "height", expression: .length(0, .meter), kind: .length)
        let height = try ParameterExpressionParser().parse("height", parameters: document.cadDocument.parameters, targetKind: .length)
        let feature = try document.createLineSketch(name: "Line", plane: .xy,
            start: SketchPoint(x: .length(0, .meter), y: height), end: point(1, 0))
        guard case .sketch(let sketch) = document.cadDocument.designGraph.nodes[feature]?.operation else { Issue.record("Missing sketch"); return }
        let entity = try #require(sketch.entityOrder.first)
        let node = try #require(document.productMetadata.sceneNodes.values.first { $0.reference?.featureID == feature })
        let target = SelectionTarget(sceneNodeID: node.id, component: .sketchEntity(.sketchPointHandle(
            featureID: feature, entityID: entity, handle: atStart ? .lineStart : .lineEnd)))
        try document.extendSketchCurve(target: target, distance: .length(2, .meter), shape: .natural)
        try document.upsertParameter(name: "height", expression: .length(1, .meter), kind: .length)
        guard case .sketch(let changed) = document.cadDocument.designGraph.nodes[feature]?.operation,
              case .line(let line) = changed.entities[entity] else { Issue.record("Missing line"); return }
        let a = try document.resolvedSketchPoint(line.start, owner: "Test")
        let b = try document.resolvedSketchPoint(line.end, owner: "Test")
        #expect(abs((b.x - a.x) + (b.y - a.y)) < 1e-10)
        #expect(abs(hypot(b.x - a.x, b.y - a.y) - sqrt(2) - 2) < 1e-10)
    }
}
