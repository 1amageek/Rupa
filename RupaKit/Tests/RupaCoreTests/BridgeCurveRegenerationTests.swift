import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

/// A Bridge Curve is derived from its source: it is regenerated whenever its sketch is committed
/// or a document parameter changes, and its control points cannot be edited directly.
@MainActor
@Suite struct BridgeCurveRegenerationTests {
    private func mm(_ value: Double) -> CADExpression { .length(value, .millimeter) }
    private func point(_ x: Double, _ y: Double) -> SketchPoint { SketchPoint(x: mm(x), y: mm(y)) }

    private struct Setup {
        var document: DesignDocument
        var featureID: FeatureID
        var firstLineID: SketchEntityID
        var secondLineID: SketchEntityID
        var bridgeID: SketchEntityID
    }

    /// Two lines, (0, 0)–(3, 0) and (6, 3)–(6, 6) mm, bridged G1 from the first's end to the
    /// second's start.
    private func setup() throws -> Setup {
        var document = DesignDocument.empty()
        let featureID = try document.createLineSketch(name: "Bridge", plane: .xy, start: point(0, 0), end: point(3, 0))
        guard var feature = document.cadDocument.designGraph.nodes[featureID],
              case var .sketch(sketch) = feature.operation,
              let firstLineID = sketch.entities.keys.first else {
            throw EditorError(code: .referenceUnresolved, message: "The line sketch is missing.")
        }
        let secondLineID = SketchEntityID()
        sketch.entities[secondLineID] = .line(SketchLine(start: point(6, 3), end: point(6, 6)))
        feature.operation = .sketch(sketch)
        document.cadDocument.designGraph.nodes[featureID] = feature
        document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
        let bridgeID = try document.createBridgeCurve(
            featureID: featureID,
            firstEndpoint: BridgeCurveEndpoint(reference: .lineEnd(firstLineID)),
            secondEndpoint: BridgeCurveEndpoint(reference: .lineStart(secondLineID)),
            continuity: .g1
        )
        return Setup(document: document, featureID: featureID, firstLineID: firstLineID, secondLineID: secondLineID, bridgeID: bridgeID)
    }

    private func sketch(_ setup: Setup) throws -> Sketch {
        guard case .sketch(let sketch) = setup.document.cadDocument.designGraph.nodes[setup.featureID]?.operation else {
            throw EditorError(code: .referenceUnresolved, message: "The sketch is missing.")
        }
        return sketch
    }

    /// The bridge's control points in meters.
    private func bridgePoints(_ setup: Setup) throws -> [Point2D] {
        guard case .spline(let spline) = try sketch(setup).entities[setup.bridgeID] else {
            throw EditorError(code: .referenceUnresolved, message: "The bridge is missing.")
        }
        let parameters = setup.document.cadDocument.parameters
        return try spline.controlPoints.map {
            Point2D(
                x: try parameters.resolvedValue(for: $0.x).value,
                y: try parameters.resolvedValue(for: $0.y).value
            )
        }
    }

    private func target(_ setup: Setup, entityID: SketchEntityID) throws -> SelectionTarget {
        guard let sceneNodeID = setup.document.productMetadata.sceneNodes.first(where: { _, node in
            node.reference?.kind == .sketch && node.reference?.featureID == setup.featureID
        })?.key else {
            throw EditorError(code: .referenceUnresolved, message: "The sketch scene node is missing.")
        }
        return SelectionTarget(
            sceneNodeID: sceneNodeID,
            component: .sketchEntity(SelectionComponentID.sketchEntity(featureID: setup.featureID, entityID: entityID))
        )
    }

    private func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) <= 1e-12 }

    @Test func movingASourceRegeneratesTheBridgeFromIt() throws {
        var setup = try setup()
        try setup.document.moveSketchEntityPoint(
            target: target(setup, entityID: setup.secondLineID),
            handle: .lineStart,
            deltaX: mm(1),
            deltaY: mm(0)
        )
        // The second line now runs from (7, 3) to (6, 6): the bridge arrives at its new start
        // along its new direction, with the new chord as the end speed.
        let points = try bridgePoints(setup)
        let chord = hypot(0.004, 0.003)
        let direction = (x: -1 / 10.0.squareRoot(), y: 3 / 10.0.squareRoot())
        #expect(points.count == 4)
        #expect(near(points[3].x, 0.007) && near(points[3].y, 0.003))
        #expect(near(points[2].x, 0.007 - chord / 3 * direction.x))
        #expect(near(points[2].y, 0.003 - chord / 3 * direction.y))
        #expect(near(points[1].x, 0.003 + chord / 3) && near(points[1].y, 0))
    }

    @Test func aParameterBoundTensionRegeneratesTheBridgeWhenItChanges() throws {
        var setup = try setup()
        try setup.document.upsertParameter(name: "reach", expression: .scalar(1.0), kind: .scalar)
        let bound = try #require(setup.document.cadDocument.parameters.parameters.values.first { $0.name == "reach" })
        let source = try #require(setup.document.productMetadata.bridgeCurveSources.values.first)
        try setup.document.setBridgeCurveParameters(
            sourceID: source.id,
            firstEndpoint: BridgeCurveEndpoint(
                reference: .lineEnd(setup.firstLineID),
                tension: BridgeCurveTension(first: .reference(bound.id), second: .scalar(1), third: .scalar(1))
            )
        )
        let chord = hypot(0.003, 0.003)
        #expect(near(try bridgePoints(setup)[1].x, 0.003 + chord / 3))

        try setup.document.upsertParameter(name: "reach", expression: .scalar(2.0), kind: .scalar)
        #expect(near(try bridgePoints(setup)[1].x, 0.003 + 2 * chord / 3))
    }

    @Test func aBridgesControlPointsCannotBeMovedOrSlid() throws {
        var setup = try setup()
        let before = setup.document.cadDocument.designGraph
        #expect(throws: EditorError.self) {
            try setup.document.moveSketchSplineControlPoint(
                target: target(setup, entityID: setup.bridgeID),
                controlPointIndex: 1,
                deltaX: mm(0),
                deltaY: mm(1)
            )
        }
        #expect(throws: EditorError.self) {
            try setup.document.slideSketchSplineControlPoints(
                target: target(setup, entityID: setup.bridgeID),
                controlPointIndexes: [1],
                direction: .normal,
                distance: mm(1)
            )
        }
        #expect(setup.document.cadDocument.designGraph == before)
    }

    /// The configuration whose Bridge Curve hooked: a rounded L of a line (0, 0)–(17, 0), an
    /// arc and a line (20, 3)–(20, 20) mm, bridged G1 from the first line's start to the last
    /// line's end. The kernel's bridge turns one way all along (no curvature sign change, where
    /// the chord-pinned two-span construction had two) with its tightest radius above 1.1 mm
    /// (0.46 mm before).
    @Test func theRoundedCornerBridgeTurnsOneWayWithoutHooks() throws {
        var document = DesignDocument.empty()
        let featureID = try document.createLineSketch(name: "L", plane: .xy, start: point(0, 0), end: point(17, 0))
        guard var feature = document.cadDocument.designGraph.nodes[featureID],
              case var .sketch(sketch) = feature.operation,
              let bottomID = sketch.entities.keys.first else {
            throw EditorError(code: .referenceUnresolved, message: "The line sketch is missing.")
        }
        let sideID = SketchEntityID()
        sketch.entities[sideID] = .line(SketchLine(start: point(20, 3), end: point(20, 20)))
        sketch.entities[SketchEntityID()] = .arc(SketchArc(
            center: point(17, 3),
            radius: mm(3),
            startAngle: .angle(-Double.pi / 2, .radian),
            endAngle: .angle(0, .radian)
        ))
        feature.operation = .sketch(sketch)
        document.cadDocument.designGraph.nodes[featureID] = feature
        document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
        let bridgeID = try document.createBridgeCurve(
            featureID: featureID,
            firstEndpoint: BridgeCurveEndpoint(reference: .lineStart(bottomID)),
            secondEndpoint: BridgeCurveEndpoint(reference: .lineEnd(sideID)),
            continuity: .g1
        )
        guard case .sketch(let result) = document.cadDocument.designGraph.nodes[featureID]?.operation,
              case .spline(let spline) = result.entities[bridgeID],
              let knots = spline.knotVector else {
            Issue.record("The bridge is missing.")
            return
        }
        let parameters = document.cadDocument.parameters
        let curve = BSplineCurve2D(
            degree: spline.degree,
            knots: knots,
            controlPoints: try spline.controlPoints.map {
                Point2D(x: try parameters.resolvedValue(for: $0.x).value, y: try parameters.resolvedValue(for: $0.y).value)
            }
        )
        let curvatures = try (0...2000).map { index -> Double in
            let geometry = try curve.differentialGeometry(at: Double(index) / 2000, tolerance: .standard)
            let d1 = geometry.firstDerivative, d2 = geometry.secondDerivative
            return (d1.x * d2.y - d1.y * d2.x) / pow(d1.x * d1.x + d1.y * d1.y, 1.5)
        }
        #expect(zip(curvatures, curvatures.dropFirst()).allSatisfy { $0 * $1 > 0 })
        #expect(1 / (curvatures.map(abs).max() ?? .infinity) > 0.0011)
    }
}
