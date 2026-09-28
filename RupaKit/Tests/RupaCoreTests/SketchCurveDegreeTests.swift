import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

/// Raise Curve Degree keeps each curve and its parameter one degree up; Convert Vertex turns a
/// vertex the spline passes through into an ordinary control point.
@MainActor
@Suite struct SketchCurveDegreeTests {
    private func mm(_ value: Double) -> CADExpression { .length(value, .millimeter) }
    private func point(_ x: Double, _ y: Double) -> SketchPoint { SketchPoint(x: mm(x), y: mm(y)) }

    private func document(_ entities: [SketchEntityID: SketchEntity]) throws -> (DesignDocument, FeatureID) {
        var document = DesignDocument.empty()
        let featureID = try document.createLineSketch(name: "Curves", plane: .xy, start: point(-20, -20), end: point(-19, -20))
        guard var feature = document.cadDocument.designGraph.nodes[featureID],
              case var .sketch(sketch) = feature.operation else {
            throw EditorError(code: .referenceUnresolved, message: "The sketch is missing.")
        }
        sketch.entities.merge(entities) { _, new in new }
        feature.operation = .sketch(sketch)
        document.cadDocument.designGraph.nodes[featureID] = feature
        document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
        return (document, featureID)
    }

    private func sketch(_ document: DesignDocument, _ featureID: FeatureID) throws -> Sketch {
        guard case .sketch(let sketch) = document.cadDocument.designGraph.nodes[featureID]?.operation else {
            throw EditorError(code: .referenceUnresolved, message: "The sketch is missing.")
        }
        return sketch
    }

    private func target(_ document: DesignDocument, _ featureID: FeatureID, _ component: SelectionComponentID) throws -> SelectionTarget {
        let sceneNodeID = try #require(document.productMetadata.sceneNodes.first { _, node in
            node.reference?.kind == .sketch && node.reference?.featureID == featureID
        }?.key)
        return SelectionTarget(sceneNodeID: sceneNodeID, component: .sketchEntity(component))
    }

    private func curve(_ document: DesignDocument, _ spline: SketchSpline) throws -> SketchSplineCurve {
        try document.resolvedSketchSplineCurve(spline, owner: "Test")
    }

    private func spline(_ document: DesignDocument, _ featureID: FeatureID, _ entityID: SketchEntityID) throws -> SketchSpline {
        guard case .spline(let spline) = try sketch(document, featureID).entities[entityID] else {
            throw EditorError(code: .referenceUnresolved, message: "The spline is missing.")
        }
        return spline
    }

    @Test func aRaisedQuinticIsTheSameCurveWithItsJointsRelationsFollowingThem() throws {
        let quinticID = SketchEntityID(), lineID = SketchEntityID()
        let quintic = SketchSpline(
            controlPoints: [(0, 0), (2, 4), (4, -2), (6, 5), (8, -1), (10, 2), (12, 5), (14, -3), (16, 4), (18, 0), (20, 2)].map { point($0.0, $0.1) },
            degree: 5
        )
        var (document, featureID) = try document([
            quinticID: .spline(quintic),
            lineID: .line(SketchLine(start: point(20, 2), end: point(25, 2))),
        ])
        try document.addSketchConstraint(featureID: featureID, constraint: .coincident(.splineControlPoint(entity: quinticID, index: 10), .lineStart(lineID)))
        try document.addSketchConstraint(featureID: featureID, constraint: .fixed(.splineControlPoint(entity: quinticID, index: 5)))
        let before = try curve(document, spline(document, featureID, quinticID))

        try document.raiseSketchCurveDegree(targets: [target(document, featureID, .sketchEntity(featureID: featureID, entityID: quinticID))])

        let raised = try spline(document, featureID, quinticID)
        #expect(raised.degree == 6 && raised.knots == nil && raised.controlPoints.count == 13)
        let after = try curve(document, raised)
        for i in 0...200 {
            let u = 2 * Double(i) / 200
            let a = try before.bSpline.point(at: u, tolerance: .standard), b = try after.bSpline.point(at: u, tolerance: .standard)
            #expect(hypot(a.x - b.x, a.y - b.y) <= 1e-12)
        }
        let constraints = try sketch(document, featureID).constraints
        #expect(constraints.contains(.coincident(.splineControlPoint(entity: quinticID, index: 12), .lineStart(lineID))))
        #expect(constraints.contains(.fixed(.splineControlPoint(entity: quinticID, index: 6))))
    }

    @Test func aRaisedLineIsADegreeTwoSplineThroughItsEnds() throws {
        let lineID = SketchEntityID(), otherID = SketchEntityID()
        var (document, featureID) = try document([
            lineID: .line(SketchLine(start: point(0, 0), end: point(10, 4))),
            otherID: .line(SketchLine(start: point(10, 4), end: point(12, 9))),
        ])
        try document.addSketchConstraint(featureID: featureID, constraint: .coincident(.lineEnd(lineID), .lineStart(otherID)))
        try document.raiseSketchCurveDegree(targets: [target(document, featureID, .sketchEntity(featureID: featureID, entityID: lineID))])
        let raised = try spline(document, featureID, lineID)
        #expect(raised.degree == 2 && raised.controlPoints.count == 3)
        let middle = raised.controlPoints[1]
        #expect(abs(try document.cadDocument.parameters.resolvedValue(for: middle.x).value - 0.005) <= 1e-15)
        #expect(abs(try document.cadDocument.parameters.resolvedValue(for: middle.y).value - 0.002) <= 1e-15)
        #expect(try sketch(document, featureID).constraints.contains(.coincident(.splineControlPoint(entity: lineID, index: 2), .lineStart(otherID))))
    }

    @Test func raisingRefusesArcsLineOnlyRelationsAndBridges() throws {
        let arcID = SketchEntityID(), lineID = SketchEntityID(), otherID = SketchEntityID()
        var (document, featureID) = try document([
            arcID: .arc(SketchArc(center: point(0, 0), radius: mm(5), startAngle: .angle(0, .radian), endAngle: .angle(1, .radian))),
            lineID: .line(SketchLine(start: point(10, 0), end: point(20, 0))),
            otherID: .line(SketchLine(start: point(30, 5), end: point(30, 15))),
        ])
        try document.addSketchConstraint(featureID: featureID, constraint: .horizontal(lineID))
        let before = document.cadDocument.designGraph
        #expect(throws: EditorError.self) {
            try document.raiseSketchCurveDegree(targets: [target(document, featureID, .sketchEntity(featureID: featureID, entityID: arcID))])
        }
        #expect(throws: EditorError.self) {
            try document.raiseSketchCurveDegree(targets: [target(document, featureID, .sketchEntity(featureID: featureID, entityID: lineID))])
        }
        #expect(document.cadDocument.designGraph == before)
        let bridgeID = try document.createBridgeCurve(
            featureID: featureID,
            firstEndpoint: BridgeCurveEndpoint(reference: .lineEnd(lineID)),
            secondEndpoint: BridgeCurveEndpoint(reference: .lineStart(otherID)),
            continuity: .g1
        )
        #expect(throws: EditorError.self) {
            try document.raiseSketchCurveDegree(targets: [target(document, featureID, .sketchEntity(featureID: featureID, entityID: bridgeID))])
        }
    }

    /// Converting the joint of a two-span cubic keeps that point as a control point the curve no
    /// longer passes through, and drops the two handles that shaped the joint.
    @Test func aConvertedVertexBecomesAControlPoint() throws {
        let splineID = SketchEntityID()
        let chain = SketchSpline(controlPoints: [(0, 0), (2, 4), (4, 4), (6, 0), (8, 4), (10, 4), (12, 0)].map { point($0.0, $0.1) })
        var (document, featureID) = try document([splineID: .spline(chain)])
        try document.convertSketchSplineVertex(target: target(document, featureID, .sketchControlPoint(featureID: featureID, entityID: splineID, index: 3)))
        let converted = try spline(document, featureID, splineID)
        #expect(converted.degree == 3)
        #expect(converted.knots == [0, 0, 0, 0, 1, 2, 2, 2, 2])
        let points = try converted.controlPoints.map { Point2D(x: try document.cadDocument.parameters.resolvedValue(for: $0.x).value * 1000, y: try document.cadDocument.parameters.resolvedValue(for: $0.y).value * 1000) }
        #expect(points.map { [$0.x, $0.y] } == [[0, 0], [2, 4], [6, 0], [10, 4], [12, 0]])
        // The curve passes near but not through the former joint (6, 0).
        let mid = try curve(document, converted).bSpline.point(at: 1, tolerance: .standard)
        #expect(hypot(mid.x * 1000 - 6, mid.y * 1000) > 1e-6)
        #expect(converted.jointIndices == [0, 4])
    }

    @Test func convertingAnEndOrANonJointIsRefused() throws {
        let splineID = SketchEntityID()
        let chain = SketchSpline(controlPoints: [(0, 0), (2, 4), (4, 4), (6, 0), (8, -4), (10, -4), (12, 0)].map { point($0.0, $0.1) })
        var (document, featureID) = try document([splineID: .spline(chain)])
        for index in [0, 2, 6] {
            #expect(throws: EditorError.self) {
                try document.convertSketchSplineVertex(target: target(document, featureID, .sketchControlPoint(featureID: featureID, entityID: splineID, index: index)))
            }
        }
    }
}
