import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

@MainActor
@Test func editableExtrudeProfileLoopPreservesReverseTraversedArcWhenRewritingCorner() async throws {
    let arcID = SketchEntityID()
    let bottomID = SketchEntityID()
    let rightID = SketchEntityID()
    let topID = SketchEntityID()
    let leftID = SketchEntityID()
    let sketch = Sketch(
        plane: .xy,
        entities: [
            arcID: .arc(
                SketchArc(
                    center: testPoint(x: 0.0, y: 0.0),
                    radius: .length(1.0, .meter),
                    startAngle: .angle(0.0, .radian),
                    endAngle: .angle(Double.pi / 2.0, .radian)
                )
            ),
            bottomID: .line(
                SketchLine(
                    start: testPoint(x: 1.0, y: 0.0),
                    end: testPoint(x: 2.0, y: 0.0)
                )
            ),
            rightID: .line(
                SketchLine(
                    start: testPoint(x: 2.0, y: 0.0),
                    end: testPoint(x: 2.0, y: 2.0)
                )
            ),
            topID: .line(
                SketchLine(
                    start: testPoint(x: 2.0, y: 2.0),
                    end: testPoint(x: 0.0, y: 2.0)
                )
            ),
            leftID: .line(
                SketchLine(
                    start: testPoint(x: 0.0, y: 2.0),
                    end: testPoint(x: 0.0, y: 1.0)
                )
            ),
        ],
        constraints: [
            .coincident(.lineEnd(bottomID), .lineStart(rightID)),
            .coincident(.lineEnd(rightID), .lineStart(topID)),
            .coincident(.lineEnd(topID), .lineStart(leftID)),
            .coincident(.lineEnd(leftID), .arcEnd(arcID)),
            .coincident(.arcStart(arcID), .lineStart(bottomID)),
        ]
    )
    let loop = try EditableExtrudeProfileLoop.editableLoop(
        in: sketch,
        document: .empty(),
        operationName: "Test rewrite"
    )
    let cornerIndex = try #require(
        loop.closestVertexIndex(
            to: EditableExtrudeProfileLoop.Point(x: 2.0, y: 0.0)
        )
    )

    let rewritten = try loop.chamferedSketch(
        targetVertexIndices: [cornerIndex],
        distance: 0.25,
        operationName: "Test rewrite"
    )

    let rewrittenArcs = rewritten.entities.values.compactMap { entity in
        if case .arc(let arc) = entity {
            return arc
        }
        return nil
    }
    let rewrittenArc = try #require(rewrittenArcs.first)
    #expect(rewrittenArcs.count == 1)
    #expect(try testAngle(rewrittenArc.startAngle) == 0.0)
    #expect(abs(try testAngle(rewrittenArc.endAngle) - Double.pi / 2.0) <= 1.0e-12)
    #expect(
        rewritten.constraints.contains { constraint in
            if case .coincident(_, .arcEnd(_)) = constraint {
                return true
            }
            return false
        }
    )
    #expect(
        rewritten.constraints.contains { constraint in
            if case .coincident(.arcStart(_), _) = constraint {
                return true
            }
            return false
        }
    )
}

@MainActor
@Test func editableExtrudeProfileLoopFilletsLineToArcCorner() async throws {
    let sketch = lineArcCornerTestSketch()
    let loop = try EditableExtrudeProfileLoop.editableLoop(
        in: sketch,
        document: .empty(),
        operationName: "Test fillet"
    )
    let cornerIndex = try #require(
        loop.closestVertexIndex(
            to: EditableExtrudeProfileLoop.Point(x: 2.0, y: 0.0)
        )
    )

    let rewritten = try loop.filletedSketch(
        targetVertexIndices: [cornerIndex],
        radius: 0.1,
        operationName: "Test fillet"
    )

    let lines = rewritten.entities.values.compactMap { entity in
        if case .line(let line) = entity {
            return line
        }
        return nil
    }
    let arcs = rewritten.entities.values.compactMap { entity in
        if case .arc(let arc) = entity {
            return arc
        }
        return nil
    }
    let measuredArcs = try arcs.map { arc in
        (arc: arc, radius: try testLength(arc.radius))
    }
    let insertedArc = try #require(measuredArcs.first { measured in
        abs(measured.radius - 0.1) <= 1.0e-12
    }?.arc)
    let sourceArc = try #require(measuredArcs.first { measured in
        abs(measured.radius - 1.0) <= 1.0e-12
    }?.arc)

    #expect(lines.count == 3)
    #expect(arcs.count == 2)
    #expect(abs(try testPointX(insertedArc.center) - (1.0 + sqrt(0.8))) <= 1.0e-12)
    #expect(abs(try testPointY(insertedArc.center) - 0.1) <= 1.0e-12)
    #expect(try testAngle(sourceArc.startAngle) > 0.0)
    #expect(abs(try testAngle(sourceArc.endAngle) - Double.pi / 2.0) <= 1.0e-12)
}

@MainActor
@Test func editableExtrudeProfileLoopFilletsArcToLineCorner() async throws {
    let sketch = lineArcCornerTestSketch()
    let loop = try EditableExtrudeProfileLoop.editableLoop(
        in: sketch,
        document: .empty(),
        operationName: "Test fillet"
    )
    let cornerIndex = try #require(
        loop.closestVertexIndex(
            to: EditableExtrudeProfileLoop.Point(x: 1.0, y: 1.0)
        )
    )

    let rewritten = try loop.filletedSketch(
        targetVertexIndices: [cornerIndex],
        radius: 0.1,
        operationName: "Test fillet"
    )

    let lines = rewritten.entities.values.compactMap { entity in
        if case .line(let line) = entity {
            return line
        }
        return nil
    }
    let arcs = rewritten.entities.values.compactMap { entity in
        if case .arc(let arc) = entity {
            return arc
        }
        return nil
    }
    let measuredArcs = try arcs.map { arc in
        (arc: arc, radius: try testLength(arc.radius))
    }
    let insertedArc = try #require(measuredArcs.first { measured in
        abs(measured.radius - 0.1) <= 1.0e-12
    }?.arc)
    let sourceArc = try #require(measuredArcs.first { measured in
        abs(measured.radius - 1.0) <= 1.0e-12
    }?.arc)

    #expect(lines.count == 3)
    #expect(arcs.count == 2)
    #expect(try testLength(insertedArc.radius) == 0.1)
    #expect(abs(try testAngle(sourceArc.startAngle) - 0.0) <= 1.0e-12)
    #expect(try testAngle(sourceArc.endAngle) > 0.0)
    #expect(try testAngle(sourceArc.endAngle) < Double.pi / 2.0)
}

@MainActor
@Test func editableExtrudeProfileLoopFilletsArcToArcCorner() async throws {
    let sketch = arcArcCornerTestSketch()
    let loop = try EditableExtrudeProfileLoop.editableLoop(
        in: sketch,
        document: .empty(),
        operationName: "Test fillet"
    )
    let cornerIndex = try #require(
        loop.closestVertexIndex(
            to: EditableExtrudeProfileLoop.Point(x: 0.0, y: 0.0)
        )
    )

    let rewritten = try loop.filletedSketch(
        targetVertexIndices: [cornerIndex],
        radius: 0.1,
        operationName: "Test fillet"
    )

    let lines = rewritten.entities.values.compactMap { entity in
        if case .line(let line) = entity {
            return line
        }
        return nil
    }
    let arcs = rewritten.entities.values.compactMap { entity in
        if case .arc(let arc) = entity {
            return arc
        }
        return nil
    }
    let measuredArcs = try arcs.map { arc in
        (arc: arc, radius: try testLength(arc.radius))
    }
    let insertedArc = try #require(measuredArcs.first { measured in
        abs(measured.radius - 0.1) <= 1.0e-12
    }?.arc)
    let previousSourceArc = try #require(measuredArcs.first { measured in
        abs(measured.radius - 1.0) <= 1.0e-12
    }?.arc)
    let currentSourceArc = try #require(measuredArcs.first { measured in
        abs(measured.radius - 2.0) <= 1.0e-12
    }?.arc)

    #expect(lines.count == 1)
    #expect(arcs.count == 3)
    #expect(abs(try testPointX(insertedArc.center) + 0.10295400907294588) <= 1.0e-12)
    #expect(abs(try testPointY(insertedArc.center) - 0.10590801814589135) <= 1.0e-12)
    #expect(abs(try testAngle(previousSourceArc.startAngle) - Double.pi) <= 1.0e-12)
    #expect(try testAngle(previousSourceArc.endAngle) > Double.pi)
    #expect(try testAngle(previousSourceArc.endAngle) < Double.pi * 1.5)
    #expect(try testAngle(currentSourceArc.startAngle) > 0.0)
    #expect(abs(try testAngle(currentSourceArc.endAngle) - Double.pi / 3.0) <= 1.0e-12)
}

private func lineArcCornerTestSketch() -> Sketch {
    let arcID = SketchEntityID()
    let bottomID = SketchEntityID()
    let diagonalID = SketchEntityID()
    let leftID = SketchEntityID()
    return Sketch(
        plane: .xy,
        entities: [
            arcID: .arc(
                SketchArc(
                    center: testPoint(x: 1.0, y: 0.0),
                    radius: .length(1.0, .meter),
                    startAngle: .angle(0.0, .radian),
                    endAngle: .angle(Double.pi / 2.0, .radian)
                )
            ),
            bottomID: .line(
                SketchLine(
                    start: testPoint(x: 0.0, y: 0.0),
                    end: testPoint(x: 2.0, y: 0.0)
                )
            ),
            diagonalID: .line(
                SketchLine(
                    start: testPoint(x: 1.0, y: 1.0),
                    end: testPoint(x: 0.0, y: 0.5)
                )
            ),
            leftID: .line(
                SketchLine(
                    start: testPoint(x: 0.0, y: 0.5),
                    end: testPoint(x: 0.0, y: 0.0)
                )
            ),
        ],
        constraints: [
            .coincident(.lineEnd(bottomID), .arcStart(arcID)),
            .coincident(.arcEnd(arcID), .lineStart(diagonalID)),
            .coincident(.lineEnd(diagonalID), .lineStart(leftID)),
            .coincident(.lineEnd(leftID), .lineStart(bottomID)),
        ]
    )
}

private func arcArcCornerTestSketch() -> Sketch {
    let previousArcID = SketchEntityID()
    let currentArcID = SketchEntityID()
    let lineID = SketchEntityID()
    return Sketch(
        plane: .xy,
        entities: [
            previousArcID: .arc(
                SketchArc(
                    center: testPoint(x: 0.0, y: 1.0),
                    radius: .length(1.0, .meter),
                    startAngle: .angle(Double.pi, .radian),
                    endAngle: .angle(Double.pi * 1.5, .radian)
                )
            ),
            currentArcID: .arc(
                SketchArc(
                    center: testPoint(x: -2.0, y: 0.0),
                    radius: .length(2.0, .meter),
                    startAngle: .angle(0.0, .radian),
                    endAngle: .angle(Double.pi / 3.0, .radian)
                )
            ),
            lineID: .line(
                SketchLine(
                    start: testPoint(x: -1.0, y: sqrt(3.0)),
                    end: testPoint(x: -1.0, y: 1.0)
                )
            ),
        ],
        constraints: [
            .coincident(.arcEnd(previousArcID), .arcStart(currentArcID)),
            .coincident(.arcEnd(currentArcID), .lineStart(lineID)),
            .coincident(.lineEnd(lineID), .arcStart(previousArcID)),
        ]
    )
}

private func testPoint(x: Double, y: Double) -> SketchPoint {
    SketchPoint(
        x: .length(x, .meter),
        y: .length(y, .meter)
    )
}

private func testPointX(_ point: SketchPoint) throws -> Double {
    let quantity = try ParameterTable().resolvedValue(for: point.x)
    #expect(quantity.kind == .length)
    return quantity.value
}

private func testPointY(_ point: SketchPoint) throws -> Double {
    let quantity = try ParameterTable().resolvedValue(for: point.y)
    #expect(quantity.kind == .length)
    return quantity.value
}

private func testLength(_ expression: CADExpression) throws -> Double {
    let quantity = try ParameterTable().resolvedValue(for: expression)
    #expect(quantity.kind == .length)
    return quantity.value
}

private func testAngle(_ expression: CADExpression) throws -> Double {
    let quantity = try ParameterTable().resolvedValue(for: expression)
    #expect(quantity.kind == .angle)
    return quantity.value
}
